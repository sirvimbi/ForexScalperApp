#!/usr/bin/env python3
"""
Clean Core ML model generator - No tensorflow conflicts
"""

import numpy as np
from sklearn.ensemble import RandomForestClassifier
import coremltools as ct
import os
import sys

print("=" * 50)
print("Creating Clean Core ML Model")
print(f"Python version: {sys.version}")
print("=" * 50)

# Define feature names
feature_names = [
    'returns', 'high_low_pct', 'close_open_pct', 'sma_10', 'sma_20', 
    'sma_50', 'ema_12', 'ema_26', 'rsi', 'macd', 'macd_signal', 
    'macd_hist', 'bb_width', 'bb_position', 'atr_pct', 'volume_ratio'
]

print(f"\n📊 Creating training data with {len(feature_names)} features...")

# Generate balanced training data
np.random.seed(42)
n_samples_per_class = 500
n_samples = n_samples_per_class * 3

X = np.random.randn(n_samples, len(feature_names)).astype(np.float32) * 0.1
y = np.array([0]*n_samples_per_class + [1]*n_samples_per_class + [2]*n_samples_per_class)
np.random.shuffle(y)

print(f"\n📊 Class distribution:")
print(f"   Neutral (0): {np.sum(y == 0)}")
print(f"   Buy (1): {np.sum(y == 1)}")
print(f"   Sell (2): {np.sum(y == 2)}")

# Train model
print(f"\n🤖 Training Random Forest model...")
model = RandomForestClassifier(
    n_estimators=10,
    max_depth=3,
    random_state=42,
    n_jobs=-1
)
model.fit(X, y)
print(f"   Model trained successfully")

# Convert to Core ML
print(f"\n🔄 Converting to Core ML...")
try:
    # Use the sklearn converter (most reliable for older coremltools)
    coreml_model = ct.converters.sklearn.convert(
        model,
        feature_names=feature_names,
        target='label'
    )
    print(f"   Conversion successful")
except Exception as e:
    print(f"   Conversion failed: {e}")
    
    # Try alternative method
    try:
        from sklearn.tree import DecisionTreeClassifier
        simple_model = DecisionTreeClassifier(max_depth=2, random_state=42)
        simple_model.fit(X, y)
        
        coreml_model = ct.converters.sklearn.convert(
            simple_model,
            feature_names=feature_names,
            target='label'
        )
        print(f"   Alternative conversion successful")
    except Exception as e2:
        print(f"   All conversions failed: {e2}")
        sys.exit(1)

# Add metadata
coreml_model.author = 'ForexScalper'
coreml_model.short_description = 'Forex trading signal predictor'
coreml_model.version = '1.0'

# Save model
output_path = 'TradingModel.mlmodel'
coreml_model.save(output_path)

print(f"\n✅ Model saved to: {output_path}")
if os.path.exists(output_path):
    file_size = os.path.getsize(output_path) / 1024
    print(f"   File size: {file_size:.1f} KB")
    
    # Verify
    try:
        loaded = ct.models.MLModel(output_path)
        print(f"   ✅ Model verified")
    except:
        print(f"   ⚠️ Model verification failed")
else:
    print(f"   ❌ File not created")

print("\n" + "=" * 50)
print("Model creation complete!")
print("=" * 50)