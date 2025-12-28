#!/bin/bash

#############################################
# CLIP Core ML Model Setup Script
# 
# This script sets up the Python environment
# and downloads/converts CLIP models for the
# Semantic Image Search macOS app.
#############################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="$SCRIPT_DIR/CLIPModels"

echo "=============================================="
echo "🚀 CLIP Core ML Model Setup"
echo "=============================================="

# Check for Python 3
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed."
    echo "   Please install Python 3.9+ from https://python.org"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "✅ Found Python $PYTHON_VERSION"

# Create virtual environment if it doesn't exist
VENV_DIR="$SCRIPT_DIR/.venv"
if [ ! -d "$VENV_DIR" ]; then
    echo ""
    echo "📦 Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# Activate virtual environment
source "$VENV_DIR/bin/activate"

# Upgrade pip
echo ""
echo "📦 Upgrading pip..."
pip install --upgrade pip --quiet

# Install dependencies
echo ""
echo "📦 Installing dependencies..."
pip install -r "$SCRIPT_DIR/requirements.txt" --quiet

# Run the download script
echo ""
python3 "$SCRIPT_DIR/download_clip_model.py" \
    --output "$MODELS_DIR" \
    --model "openai/clip-vit-base-patch32" \
    --verify

# Copy to project resources
echo ""
echo "📦 Installing models to project..."
RESOURCES_DIR="$PROJECT_DIR/SemanticImageSearch/Resources"
mkdir -p "$RESOURCES_DIR"

# Copy model packages
for model in "$MODELS_DIR"/*.mlpackage; do
    if [ -d "$model" ]; then
        model_name=$(basename "$model")
        echo "   Copying $model_name..."
        rm -rf "$RESOURCES_DIR/$model_name"
        cp -R "$model" "$RESOURCES_DIR/"
    fi
done

# Copy compiled models if available
for model in "$MODELS_DIR"/*.mlmodelc; do
    if [ -d "$model" ]; then
        model_name=$(basename "$model")
        echo "   Copying $model_name..."
        rm -rf "$RESOURCES_DIR/$model_name"
        cp -R "$model" "$RESOURCES_DIR/"
    fi
done

# Copy config files
for file in clip_config.json clip_vocab.json clip_merges.txt; do
    if [ -f "$MODELS_DIR/$file" ]; then
        echo "   Copying $file..."
        cp "$MODELS_DIR/$file" "$RESOURCES_DIR/"
    fi
done

echo ""
echo "=============================================="
echo "✅ Setup complete!"
echo "=============================================="
echo ""
echo "Models installed to: $RESOURCES_DIR"
echo ""
echo "Next steps:"
echo "1. Open SemanticImageSearch.xcodeproj in Xcode"
echo "2. Add the model files to the project if not already added"
echo "3. Build and run the app"
echo ""
