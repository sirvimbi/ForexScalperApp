#!/usr/bin/env python3
"""
Create a valid Core ML model for forex trading
"""

import coremltools as ct
from coremltools.models import MLModel
from coremltools.models.datatypes import Array
from coremltools.models.neural_network import NeuralNetworkBuilder
import numpy as np
import os

print("=" * 50)
print("Creating Valid Core ML Model")
print("=" * 50)

# Define input features (16 technical indicators)
feature_names = [
    'returns', 'high_low_pct', 'close_open_pct', 'sma_10', 'sma_20', 
    'sma_50', 'ema_12', 'ema_26', 'rsi', 'macd', 'macd_signal', 
    'macd_hist', 'bb_width', 'bb_position', 'atr_pct', 'volume_ratio'
]

# Create input specification
input_features = [('features', Array(1, 16))]  # 1x16 array
output_features = [('target', Array(1, 3))]     # 3 output classes

# Build a simple neural network
builder = NeuralNetworkBuilder(input_features, output_features)

# First hidden layer
builder.add_inner_product(
    name='hidden1',
    W=np.random.randn(32, 16).astype(np.float32) * 0.1,
    b=np.zeros(32).astype(np.float32),
    input_channels=16,
    output_channels=32,
    has_bias=True,
    input_name='features',
    output_name='hidden1_out'
)

# Add ReLU activation
builder.add_activation(
    name='relu1',
    non_linearity='RELU',
    input_name='hidden1_out',
    output_name='relu1_out'
)

# Second hidden layer
builder.add_inner_product(
    name='hidden2',
    W=np.random.randn(16, 32).astype(np.float32) * 0.1,
    b=np.zeros(16).astype(np.float32),
    input_channels=32,
    output_channels=16,
    has_bias=True,
    input_name='relu1_out',
    output_name='hidden2_out'
)

# Add ReLU activation
builder.add_activation(
    name='relu2',
    non_linearity='RELU',
    input_name='hidden2_out',
    output_name='relu2_out'
)

# Output layer
builder.add_inner_product(
    name='output_layer',
    W=np.random.randn(3, 16).astype(np.float32) * 0.1,
    b=np.zeros(3).astype(np.float32),
    input_channels=16,
    output_channels=3,
    has_bias=True,
    input_name='relu2_out',
    output_name='output'
)

# Add softmax for probabilities
builder.add_softmax(
    name='softmax',
    input_name='output',
    output_name='target'
)

# Get the spec
spec = builder.spec

# Clear existing outputs
while len(spec.description.output) > 0:
    spec.description.output.pop()

# Configure inputs
spec.description.input[0].name = 'features'
spec.description.input[0].shortDescription = 'Array of 16 technical indicators'

# Add target output
target_output = spec.description.output.add()
target_output.name = 'target'
target_output.shortDescription = 'Predicted class (0=neutral, 1=buy, 2=sell)'
target_output.type.multiArrayType.dataType = ct.proto.FeatureTypes_pb2.ArrayFeatureType.INT32
target_output.type.multiArrayType.shape.extend([3])

# Add probability output with proper dictionary type
prob_output = spec.description.output.add()
prob_output.name = 'targetProbability'
prob_output.shortDescription = 'Probability distribution over classes'
prob_output.type.dictionaryType.stringKeyType.SetInParent()

# Set predicted feature names
spec.description.predictedFeatureName = 'target'
spec.description.predictedProbabilitiesName = 'targetProbability'

# Add metadata
spec.description.metadata.shortDescription = 'Predicts buy/sell signals for forex trading'
spec.description.metadata.author = 'ForexScalper'
spec.description.metadata.versionString = '1.0'
spec.description.metadata.license = 'Private'

# Add feature names as metadata
user_defined = spec.description.metadata.userDefined
user_defined['feature_names'] = ','.join(feature_names)
user_defined['classes'] = 'neutral,buy,sell'
user_defined['input_shape'] = '1x16'
user_defined['output_shape'] = '3'

# Create the model
mlmodel = MLModel(spec)

# Save the model
output_path = 'TradingModel.mlmodel'
mlmodel.save(output_path)

print(f"\n✅ Valid Core ML model saved to: {output_path}")
print(f"   Features: {len(feature_names)} technical indicators")
print(f"   Input shape: 1x16 array")
print(f"   Output classes: neutral (0), buy (1), sell (2)")
print(f"   File size: {os.path.getsize(output_path) / 1024:.1f} KB")

# Verify the model
print("\n🔍 Verifying model...")
try:
    # Try to load it back
    test_model = ct.models.MLModel(output_path)
    print(f"   ✓ Model loaded successfully")
    print(f"   ✓ Inputs: {[inp.name for inp in test_model.get_spec().description.input]}")
    print(f"   ✓ Outputs: {[out.name for out in test_model.get_spec().description.output]}")
except Exception as e:
    print(f"   ✗ Verification failed: {e}")

print("\n" + "=" * 50)
print("Model creation complete!")
print("=" * 50)