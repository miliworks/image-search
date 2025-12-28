#!/usr/bin/env python3
"""
CLIP Core ML Model Download and Conversion Script

This script downloads the CLIP model from Hugging Face and converts it to Core ML format
for use in the Semantic Image Search macOS application.

Requirements:
    pip install torch torchvision transformers coremltools Pillow numpy

Usage:
    python download_clip_model.py

The script will create:
    - CLIPImageEncoder.mlpackage (Image encoder)
    - CLIPTextEncoder.mlpackage (Text encoder)
"""

import os
import sys
import shutil
import argparse
from pathlib import Path

def check_dependencies():
    """Check if all required dependencies are installed."""
    missing = []
    
    try:
        import torch
    except ImportError:
        missing.append("torch")
    
    try:
        import torchvision
    except ImportError:
        missing.append("torchvision")
    
    try:
        import transformers
    except ImportError:
        missing.append("transformers")
    
    try:
        import coremltools
    except ImportError:
        missing.append("coremltools")
    
    try:
        from PIL import Image
    except ImportError:
        missing.append("Pillow")
    
    try:
        import numpy
    except ImportError:
        missing.append("numpy")
    
    if missing:
        print("❌ Missing dependencies. Please install them:")
        print(f"   pip install {' '.join(missing)}")
        sys.exit(1)
    
    print("✅ All dependencies installed")


def download_and_convert_clip(output_dir: Path, model_name: str = "openai/clip-vit-base-patch32"):
    """Download CLIP model and convert to Core ML format."""
    import torch
    import coremltools as ct
    from transformers import CLIPModel, CLIPProcessor, CLIPTokenizer
    from PIL import Image
    import numpy as np
    
    print(f"\n📥 Downloading CLIP model: {model_name}")
    
    # Download model and processor
    model = CLIPModel.from_pretrained(model_name)
    processor = CLIPProcessor.from_pretrained(model_name)
    tokenizer = CLIPTokenizer.from_pretrained(model_name)
    
    model.eval()
    
    print("✅ Model downloaded successfully")
    
    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # ==================== Image Encoder ====================
    print("\n🖼️  Converting Image Encoder...")
    
    class CLIPImageEncoderWrapper(torch.nn.Module):
        def __init__(self, clip_model):
            super().__init__()
            self.vision_model = clip_model.vision_model
            self.visual_projection = clip_model.visual_projection
        
        def forward(self, pixel_values):
            vision_outputs = self.vision_model(pixel_values=pixel_values)
            image_embeds = vision_outputs.pooler_output
            image_embeds = self.visual_projection(image_embeds)
            # Normalize
            image_embeds = image_embeds / image_embeds.norm(p=2, dim=-1, keepdim=True)
            return image_embeds
    
    image_encoder = CLIPImageEncoderWrapper(model)
    image_encoder.eval()
    
    # Create example input (224x224 RGB image)
    example_image = torch.randn(1, 3, 224, 224)
    
    # Trace the model
    traced_image_encoder = torch.jit.trace(image_encoder, example_image)
    
    # Convert to Core ML
    image_encoder_mlmodel = ct.convert(
        traced_image_encoder,
        inputs=[
            ct.TensorType(
                name="image",
                shape=(1, 3, 224, 224),
                dtype=np.float32
            )
        ],
        outputs=[
            ct.TensorType(name="embedding", dtype=np.float32)
        ],
        minimum_deployment_target=ct.target.macOS13,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram"
    )
    
    # Set metadata
    image_encoder_mlmodel.author = "Semantic Image Search"
    image_encoder_mlmodel.short_description = "CLIP Image Encoder (ViT-B/32)"
    image_encoder_mlmodel.version = "1.0"
    
    # Add input description
    spec = image_encoder_mlmodel.get_spec()
    spec.description.input[0].shortDescription = "RGB image normalized to [-1, 1], shape (1, 3, 224, 224)"
    spec.description.output[0].shortDescription = "512-dimensional normalized embedding"
    
    # Save
    image_encoder_path = output_dir / "CLIPImageEncoder.mlpackage"
    image_encoder_mlmodel.save(str(image_encoder_path))
    print(f"✅ Image Encoder saved to: {image_encoder_path}")
    
    # ==================== Text Encoder ====================
    print("\n📝 Converting Text Encoder...")
    
    class CLIPTextEncoderWrapper(torch.nn.Module):
        def __init__(self, clip_model):
            super().__init__()
            self.text_model = clip_model.text_model
            self.text_projection = clip_model.text_projection
        
        def forward(self, input_ids, attention_mask):
            text_outputs = self.text_model(
                input_ids=input_ids,
                attention_mask=attention_mask
            )
            text_embeds = text_outputs.pooler_output
            text_embeds = self.text_projection(text_embeds)
            # Normalize
            text_embeds = text_embeds / text_embeds.norm(p=2, dim=-1, keepdim=True)
            return text_embeds
    
    text_encoder = CLIPTextEncoderWrapper(model)
    text_encoder.eval()
    
    # Create example input (max 77 tokens)
    max_length = 77
    example_input_ids = torch.zeros(1, max_length, dtype=torch.long)
    example_attention_mask = torch.ones(1, max_length, dtype=torch.long)
    
    # Trace the model
    traced_text_encoder = torch.jit.trace(
        text_encoder, 
        (example_input_ids, example_attention_mask)
    )
    
    # Convert to Core ML
    text_encoder_mlmodel = ct.convert(
        traced_text_encoder,
        inputs=[
            ct.TensorType(
                name="input_ids",
                shape=(1, max_length),
                dtype=np.int32
            ),
            ct.TensorType(
                name="attention_mask",
                shape=(1, max_length),
                dtype=np.int32
            )
        ],
        outputs=[
            ct.TensorType(name="embedding", dtype=np.float32)
        ],
        minimum_deployment_target=ct.target.macOS13,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram"
    )
    
    # Set metadata
    text_encoder_mlmodel.author = "Semantic Image Search"
    text_encoder_mlmodel.short_description = "CLIP Text Encoder (ViT-B/32)"
    text_encoder_mlmodel.version = "1.0"
    
    # Save
    text_encoder_path = output_dir / "CLIPTextEncoder.mlpackage"
    text_encoder_mlmodel.save(str(text_encoder_path))
    print(f"✅ Text Encoder saved to: {text_encoder_path}")
    
    # ==================== Save Tokenizer Vocabulary ====================
    print("\n📚 Saving tokenizer vocabulary...")
    
    vocab = tokenizer.get_vocab()
    vocab_path = output_dir / "clip_vocab.json"
    
    import json
    with open(vocab_path, 'w', encoding='utf-8') as f:
        json.dump(vocab, f, ensure_ascii=False, indent=2)
    
    # Save merges file for BPE
    merges_path = output_dir / "clip_merges.txt"
    if hasattr(tokenizer, 'bpe_ranks'):
        with open(merges_path, 'w', encoding='utf-8') as f:
            f.write("#version: 0.2\n")
            for merge, rank in sorted(tokenizer.bpe_ranks.items(), key=lambda x: x[1]):
                f.write(f"{merge[0]} {merge[1]}\n")
    
    print(f"✅ Vocabulary saved to: {vocab_path}")
    
    # ==================== Create Config File ====================
    print("\n⚙️  Creating configuration file...")
    
    config = {
        "model_name": model_name,
        "image_size": 224,
        "embedding_dim": 512,
        "max_text_length": 77,
        "mean": [0.48145466, 0.4578275, 0.40821073],
        "std": [0.26862954, 0.26130258, 0.27577711],
        "image_encoder": "CLIPImageEncoder.mlpackage",
        "text_encoder": "CLIPTextEncoder.mlpackage",
        "vocab_file": "clip_vocab.json"
    }
    
    config_path = output_dir / "clip_config.json"
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)
    
    print(f"✅ Configuration saved to: {config_path}")
    
    return image_encoder_path, text_encoder_path


def compile_models(output_dir: Path):
    """Compile mlpackage to mlmodelc for faster loading."""
    import subprocess
    
    print("\n🔧 Compiling models for faster loading...")
    
    for mlpackage in output_dir.glob("*.mlpackage"):
        mlmodelc = mlpackage.with_suffix(".mlmodelc")
        
        try:
            result = subprocess.run(
                ["xcrun", "coremlcompiler", "compile", str(mlpackage), str(output_dir)],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                print(f"✅ Compiled: {mlmodelc.name}")
            else:
                print(f"⚠️  Could not compile {mlpackage.name}: {result.stderr}")
        except FileNotFoundError:
            print("⚠️  xcrun not found. Skipping compilation (mlpackage will still work).")
            break


def copy_to_project(output_dir: Path, project_resources: Path):
    """Copy models to the Xcode project resources folder."""
    print("\n📦 Copying models to project...")
    
    if not project_resources.exists():
        project_resources.mkdir(parents=True)
    
    # Copy mlmodelc (compiled) or mlpackage files
    for model_dir in output_dir.iterdir():
        if model_dir.suffix in ['.mlmodelc', '.mlpackage']:
            dest = project_resources / model_dir.name
            if dest.exists():
                shutil.rmtree(dest)
            shutil.copytree(model_dir, dest)
            print(f"✅ Copied: {model_dir.name}")
    
    # Copy config and vocab
    for file in ['clip_config.json', 'clip_vocab.json', 'clip_merges.txt']:
        src = output_dir / file
        if src.exists():
            shutil.copy(src, project_resources / file)
            print(f"✅ Copied: {file}")


def verify_models(output_dir: Path):
    """Verify the converted models work correctly."""
    import coremltools as ct
    import numpy as np
    
    print("\n🧪 Verifying models...")
    
    # Test image encoder
    image_encoder_path = output_dir / "CLIPImageEncoder.mlpackage"
    if image_encoder_path.exists():
        model = ct.models.MLModel(str(image_encoder_path))
        test_image = np.random.randn(1, 3, 224, 224).astype(np.float32)
        result = model.predict({"image": test_image})
        embedding = result["embedding"]
        print(f"✅ Image Encoder: Output shape {embedding.shape}, norm={np.linalg.norm(embedding):.4f}")
    
    # Test text encoder
    text_encoder_path = output_dir / "CLIPTextEncoder.mlpackage"
    if text_encoder_path.exists():
        model = ct.models.MLModel(str(text_encoder_path))
        test_ids = np.zeros((1, 77), dtype=np.int32)
        test_mask = np.ones((1, 77), dtype=np.int32)
        result = model.predict({"input_ids": test_ids, "attention_mask": test_mask})
        embedding = result["embedding"]
        print(f"✅ Text Encoder: Output shape {embedding.shape}, norm={np.linalg.norm(embedding):.4f}")


def main():
    parser = argparse.ArgumentParser(
        description="Download and convert CLIP model to Core ML format"
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=Path("./CLIPModels"),
        help="Output directory for models (default: ./CLIPModels)"
    )
    parser.add_argument(
        "--model", "-m",
        type=str,
        default="openai/clip-vit-base-patch32",
        choices=[
            "openai/clip-vit-base-patch32",
            "openai/clip-vit-base-patch16",
            "openai/clip-vit-large-patch14"
        ],
        help="CLIP model variant to download"
    )
    parser.add_argument(
        "--install-to-project",
        action="store_true",
        help="Copy models to the Xcode project Resources folder"
    )
    parser.add_argument(
        "--skip-compile",
        action="store_true",
        help="Skip compiling mlpackage to mlmodelc"
    )
    parser.add_argument(
        "--verify",
        action="store_true",
        help="Verify models after conversion"
    )
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("🚀 CLIP Core ML Model Download & Conversion")
    print("=" * 60)
    
    # Check dependencies
    check_dependencies()
    
    # Download and convert
    download_and_convert_clip(args.output, args.model)
    
    # Compile models
    if not args.skip_compile:
        compile_models(args.output)
    
    # Verify
    if args.verify:
        verify_models(args.output)
    
    # Copy to project
    if args.install_to_project:
        script_dir = Path(__file__).parent
        project_resources = script_dir.parent / "SemanticImageSearch" / "Resources"
        copy_to_project(args.output, project_resources)
    
    print("\n" + "=" * 60)
    print("✅ Done! Models are ready to use.")
    print("=" * 60)
    
    print(f"""
Next steps:
1. Add the models to your Xcode project:
   - Drag {args.output}/CLIPImageEncoder.mlpackage to Resources/
   - Drag {args.output}/CLIPTextEncoder.mlpackage to Resources/
   - Drag {args.output}/clip_config.json to Resources/
   - Drag {args.output}/clip_vocab.json to Resources/

2. Or run with --install-to-project flag to auto-copy

3. Update VectorService.swift to use the CLIP models
""")


if __name__ == "__main__":
    main()
