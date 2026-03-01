#!/usr/bin/env python3
"""
Create Core ML model for forex trading - Simple approach
"""

import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
import coremltools as ct
import os

print("=" * 50)
print("Creating Forex Trading Model - Simple Approach")
print("=" * 50)

# Define feature names
feature_names = [
    'returns', 'high_low_pct', 'close_open_pct', 'sma_10', 'sma_20', 
    'sma_50', 'ema_12', 'ema_26', 'rsi', 'macd', 'macd_signal', 
    'macd_hist', 'bb_width', 'bb_position', 'atr_pct', 'volume_ratio'
]

# Create training data
np.random.seed(42)
n_samples_per_class = 1000
n_samples = n_samples_per_class * 3

X = np.random.randn(n_samples, len(feature_names)) * 0.1
y = np.array([0]*n_samples_per_class + [1]*n_samples_per_class + [2]*n_samples_per_class)
np.random.shuffle(y)

# Create a pipeline
pipeline = Pipeline([
    ('scaler', StandardScaler()),
    ('classifier', RandomForestClassifier(
        n_estimators=20,
        max_depth=5,
        min_samples_split=20,
        random_state=42,
        n_jobs=-1
    ))
])

print(f"\n🤖 Training pipeline model...")
pipeline.fit(X, y)

# Convert to Core ML - ULTRA SIMPLE VERSION
print(f"\n🔄 Converting to Core ML...")

# The simplest possible conversion
coreml_model = ct.converters.sklearn.convert(
    pipeline,
    feature_names=feature_names,
    target='label'
)

# Add metadata
coreml_model.author = 'ForexScalper'
coreml_model.short_description = 'Forex trading signal predictor'
coreml_model.version = '1.0'

# Save the model
output_path = 'TradingModel.mlmodel'
coreml_model.save(output_path)

print(f"\n✅ Model saved to: {output_path}")

print("\n" + "=" * 50)
print("Model creation complete!")
print("=" * 50)