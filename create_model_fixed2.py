#!/usr/bin/env python3
"""
Create Core ML model for forex trading - Fixed with proper outputs
"""

import numpy as np
from sklearn.ensemble import RandomForestClassifier
import coremltools as ct
from coremltools.models import MLModel
import os
import sys

print("=" * 50)
print("Creating Forex Trading Model - Fixed")
print(f"Python version: {sys.version}")
print("=" * 50)

# Define feature names
feature_names = [
    'returns', 'high_low_pct', 'close_open_pct', 'sma_10', 'sma_20', 
    'sma_50', 'ema_12', 'ema_26', 'rsi', 'macd', 'macd_signal', 
    'macd_hist', 'bb_width', 'bb_position', 'atr_pct', 'volume_ratio'
]

print(f"\n📊 Creating balanced training data...")

# Generate synthetic training data with balanced classes
np.random.seed(42)
n_samples_per_class = 1000  # 1000 each for sell, neutral, buy
n_samples = n_samples_per_class * 3

# Create feature matrix
X = np.random.randn(n_samples, len(feature_names)) * 0.1

# Create balanced labels (0: sell, 1: neutral, 2: buy)
y = np.array([0]*n_samples_per_class + [1]*n_samples_per_class + [2]*n_samples_per_class)
np.random.shuffle(y)  # Shuffle the labels

# Add some pattern to features based on labels
for i in range(len(X)):
    if y[i] == 2:  # Buy
        X[i, 0] += 0.3  # returns positive
        X[i, 8] -= 0.4  # rsi lower (oversold)
        X[i, 3] += 0.2  # sma_10 positive
    elif y[i] == 0:  # Sell
        X[i, 0] -= 0.3  # returns negative
        X[i, 8] += 0.4  # rsi higher (overbought)
        X[i, 3] -= 0.2  # sma_10 negative

print(f"\n📊 Class distribution:")
print(f"   Sell (0): {np.sum(y == 0)} samples")
print(f"   Neutral (1): {np.sum(y == 1)} samples")
print(f"   Buy (2): {np.sum(y == 2)} samples")

# Train model
print(f"\n🤖 Training Random Forest model...")
model = RandomForestClassifier(
    n_estimators=20,
    max_depth=5,
    min_samples_split=20,
    random_state=42,
    n_jobs=-1
)
model.fit(X, y)
print(f"   Model trained successfully")

# Convert to Core ML with proper output specification
print(f"\n🔄 Converting to Core ML...")

# Define input features
input_features = [ct.Feature(name, ct.DoubleType()) for name in feature_names]

# Define output - using Classifier configuration
output_feature = ct.Feature('label', ct.Int64Type())

# Create the model spec
model_spec = ct.converters.sklearn.convert(
    model,
    feature_names=feature_names,
    target='label',
    # Specify output types
    predicted_feature_name='label',
    predicted_probabilities_output='labelProbability'
)

# Add metadata
model_spec.author = 'ForexScalper'
model_spec.short_description = 'Predicts buy/sell signals for forex trading'
model_spec.version = '1.0'
model_spec.license = 'For educational purposes'

# Ensure the model has proper output types
spec = model_spec.get_spec()
print(f"Model type: {spec.WhichOneof('Type')}")
print(f"Inputs: {[input.name for input in spec.description.input]}")
print(f"Outputs: {[output.name for output in spec.description.output]}")

# Save the model
output_path = 'TradingModel.mlmodel'
model_spec.save(output_path)

print(f"\n✅ Model saved to: {output_path}")
if os.path.exists(output_path):
    file_size = os.path.getsize(output_path) / 1024
    print(f"   File size: {file_size:.1f} KB")
    
    # Try to compile it
    print(f"\n🔧 Testing compilation...")
    try:
        import subprocess
        result = subprocess.run(
            ['xcrun', 'coremlc', 'compile', output_path, '.'],
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            print(f"   ✅ Compilation successful!")
        else:
            print(f"   ❌ Compilation failed: {result.stderr}")
    except Exception as e:
        print(f"   ⚠️ Could not test compilation: {e}")
    
    # Print model info
    print(f"\n📋 Model info:")
    print(f"   Input features: {len(feature_names)}")
    print(f"   Output classes: sell(0), neutral(1), buy(2)")
    print(f"   Feature names:")
    for i, name in enumerate(feature_names[:5]):
        print(f"     - {name}")
    print(f"     - ... and {len(feature_names)-5} more")
else:
    print(f"   ❌ File not found!")

print("\n" + "=" * 50)
print("Model creation complete!")
print("=" * 50)