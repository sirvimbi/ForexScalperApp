#!/usr/bin/env python3
"""
Create Core ML model for forex trading - CoreMLTools 6.0+ API
"""

import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
import coremltools as ct
from coremltools.models import MLModel
from coremltools.models.utils import save_spec
import os

print("=" * 50)
print("Creating Forex Trading Model - CoreMLTools 6.0+")
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

# Convert to Core ML
print(f"\n🔄 Converting to Core ML...")

# For scikit-learn models in newer CoreMLTools
# We need to use the correct converter
try:
    # Try the unified API first
    coreml_model = ct.convert(
        pipeline,
        convert_to="mlprogram",  # or "neuralnetwork"
        compute_precision=ct.precision.FLOAT32
    )
except:
    try:
        # Fallback to sklearn specific converter
        import coremltools.converters.sklearn as skl_converter
        coreml_model = skl_converter.convert(pipeline)
    except:
        # Manual conversion approach
        print("Using manual conversion...")
        
        # Train a standalone classifier (simpler for conversion)
        classifier = RandomForestClassifier(
            n_estimators=20,
            max_depth=5,
            min_samples_split=20,
            random_state=42
        )
        classifier.fit(X, y)
        
        # Convert just the classifier
        coreml_model = ct.convert(
            classifier,
            inputs=[ct.TensorType(name="features", shape=(1, len(feature_names)))]
        )

# Add metadata
coreml_model.author = 'ForexScalper'
coreml_model.short_description = 'Forex trading signal predictor (0=sell, 1=buy, 2=hold)'
coreml_model.version = '1.0'

# Save the model
output_path = 'TradingModel.mlmodel'
coreml_model.save(output_path)

print(f"\n✅ Model saved to: {output_path}")

print("\n" + "=" * 50)
print("Model creation complete!")
print("=" * 50)