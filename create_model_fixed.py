#!/usr/bin/env python3
"""
Create Core ML model for forex trading - Fixed version
"""

import numpy as np
from sklearn.ensemble import RandomForestClassifier
import coremltools as ct
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
n_samples_per_class = 1000  # 1000 each for neutral, buy, sell
n_samples = n_samples_per_class * 3

# Create feature matrix
X = np.random.randn(n_samples, len(feature_names)) * 0.1

# Create balanced labels
y = np.array([0]*n_samples_per_class + [1]*n_samples_per_class + [2]*n_samples_per_class)
np.random.shuffle(y)  # Shuffle the labels

# Add some pattern to features based on labels
for i in range(len(X)):
    if y[i] == 1:  # Buy
        X[i, 0] += 0.3  # returns positive
        X[i, 8] -= 0.4  # rsi lower (oversold)
        X[i, 3] += 0.2  # sma_10 positive
    elif y[i] == 2:  # Sell
        X[i, 0] -= 0.3  # returns negative
        X[i, 8] += 0.4  # rsi higher (overbought)
        X[i, 3] -= 0.2  # sma_10 negative

print(f"\n📊 Class distribution:")
print(f"   Neutral (0): {np.sum(y == 0)} samples")
print(f"   Buy (1): {np.sum(y == 1)} samples")
print(f"   Sell (2): {np.sum(y == 2)} samples")

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
print(f"   Feature importance: {model.feature_importances_[:5]}...")

# Convert to Core ML - using the correct API for older version
print(f"\n🔄 Converting to Core ML...")
try:
    # For coremltools 6.0.0, the API is different
    coreml_model = ct.converters.sklearn.convert(
        model,
        feature_names=feature_names,
        target='label'
    )
    print(f"   Conversion successful")
except Exception as e:
    print(f"   Conversion failed: {e}")
    
    # Try alternative API
    try:
        print("   Trying alternative conversion method...")
        from sklearn.tree import DecisionTreeClassifier
        
        # Train a simpler model
        simple_model = DecisionTreeClassifier(max_depth=3, random_state=42)
        simple_model.fit(X, y)
        
        coreml_model = ct.converters.sklearn.convert(
            simple_model,
            feature_names=feature_names,
            target='label'
        )
        print(f"   Alternative conversion successful")
    except Exception as e2:
        print(f"   Alternative conversion also failed: {e2}")
        sys.exit(1)

# Add metadata
coreml_model.author = 'ForexScalper'
coreml_model.short_description = 'Predicts buy/sell signals for forex trading'
coreml_model.version = '1.0'

# Save the model
output_path = 'TradingModel.mlmodel'
coreml_model.save(output_path)

print(f"\n✅ Model saved to: {output_path}")
if os.path.exists(output_path):
    file_size = os.path.getsize(output_path) / 1024
    print(f"   File size: {file_size:.1f} KB")
    
    # Print model info
    print(f"\n📋 Model info:")
    print(f"   Input features: {len(feature_names)}")
    print(f"   Output classes: neutral(0), buy(1), sell(2)")
else:
    print(f"   ❌ File not found!")

print("\n" + "=" * 50)
print("Model creation complete!")
print("=" * 50)