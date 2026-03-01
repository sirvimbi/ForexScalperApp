#!/usr/bin/env python3
"""
Create Core ML model using ONNX intermediate format
"""

import numpy as np
from sklearn.ensemble import RandomForestClassifier
import onnx
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType
import coremltools as ct
import os

print("=" * 50)
print("Creating Forex Trading Model via ONNX")
print("=" * 50)

# Define feature names
feature_names = [
    'returns', 'high_low_pct', 'close_open_pct', 'sma_10', 'sma_20', 
    'sma_50', 'ema_12', 'ema_26', 'rsi', 'macd', 'macd_signal', 
    'macd_hist', 'bb_width', 'bb_position', 'atr_pct', 'volume_ratio'
]

# Create balanced data
np.random.seed(42)
n_samples = 3000
X = np.random.randn(n_samples, len(feature_names)).astype(np.float32)
y = np.random.randint(0, 3, n_samples)

# Train model
model = RandomForestClassifier(n_estimators=10, max_depth=4)
model.fit(X, y)

# Convert to ONNX
initial_type = [('float_input', FloatTensorType([None, len(feature_names)]))]
onnx_model = convert_sklearn(model, initial_types=initial_type)

# Save ONNX
onnx.save_model(onnx_model, 'model.onnx')

# Convert ONNX to Core ML
coreml_model = ct.converters.onnx.convert(model='model.onnx')

# Save Core ML
coreml_model.save('TradingModel.mlmodel')

print("✅ Model created successfully")