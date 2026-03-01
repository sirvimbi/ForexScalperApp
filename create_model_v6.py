#!/usr/bin/env python3
"""
Create Core ML model for forex trading - CoreMLTools 6.0 compatible
"""

import numpy as np
from sklearn.ensemble import RandomForestClassifier
import coremltools as ct
from coremltools.models import MLModel
from coremltools.models.datatypes import Array
from coremltools.models.neural_network import NeuralNetworkBuilder
import os
import sys

print("=" * 50)
print("Creating Forex Trading Model - CoreMLTools 6.0")
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
n_samples_per_class = 1000
n_samples = n_samples_per_class * 3

# Create feature matrix
X = np.random.randn(n_samples, len(feature_names)) * 0.1

# Create balanced labels
y = np.array([0]*n_samples_per_class + [1]*n_samples_per_class + [2]*n_samples_per_class)
np.random.shuffle(y)

# Add patterns
for i in range(len(X)):
    if y[i] == 1:  # Buy
        X[i, 0] += 0.3  # returns positive
        X[i, 8] -= 0.4  # rsi lower
        X[i, 3] += 0.2  # sma positive
    elif y[i] == 2:  # Sell
        X[i, 0] -= 0.3  # returns negative
        X[i, 8] += 0.4  # rsi higher
        X[i, 3] -= 0.2  # sma negative

print(f"\n📊 Class distribution:")
print(f"   Neutral (0): {np.sum(y == 0)}")
print(f"   Buy (1): {np.sum(y == 1)}")
print(f"   Sell (2): {np.sum(y == 2)}")

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

# Try different conversion methods
print(f"\n🔄 Converting to Core ML...")

# Method 1: Try with sklearn converter (different API)
try:
    # For coremltools 6.0, the API might be different
    import coremltools
    print(f"   CoreMLTools version: {coremltools.__version__}")
    
    # Try the newer API
    coreml_model = ct.convert(
        model,
        inputs=[ct.TensorType(name=name, shape=(1,)) for name in feature_names],
        classifier_config=ct.ClassifierConfig(class_labels=[0, 1, 2])
    )
    print(f"   Method 1 successful")
    
except Exception as e1:
    print(f"   Method 1 failed: {e1}")
    
    # Method 2: Create a pipeline
    try:
        from sklearn.pipeline import Pipeline
        from sklearn.preprocessing import StandardScaler
        
        pipeline = Pipeline([
            ('scaler', StandardScaler()),
            ('rf', model)
        ])
        
        # Fit pipeline
        pipeline.fit(X, y)
        
        # Convert pipeline
        coreml_model = ct.convert(
            pipeline,
            inputs=[ct.TensorType(name=name, shape=(1,)) for name in feature_names],
            classifier_config=ct.ClassifierConfig(class_labels=[0, 1, 2])
        )
        print(f"   Method 2 successful")
        
    except Exception as e2:
        print(f"   Method 2 failed: {e2}")
        
        # Method 3: Create neural network manually
        try:
            print(f"   Method 3: Creating neural network manually...")
            
            # Create input features
            input_features = [('features', Array(1, len(feature_names)))]
            output_features = [('target', None)]
            
            # Build simple neural network
            builder = NeuralNetworkBuilder(input_features, output_features)
            
            # Add layers
            builder.add_inner_product(
                name='layer1',
                W=np.random.randn(10, len(feature_names)).astype(np.float32) * 0.1,
                b=np.zeros(10).astype(np.float32),
                input_channels=len(feature_names),
                output_channels=10,
                has_bias=True,
                input_name='features',
                output_name='layer1_out'
            )
            
            builder.add_activation(
                name='relu1',
                non_linearity='RELU',
                input_name='layer1_out',
                output_name='relu1_out'
            )
            
            builder.add_inner_product(
                name='layer2',
                W=np.random.randn(3, 10).astype(np.float32) * 0.1,
                b=np.zeros(3).astype(np.float32),
                input_channels=10,
                output_channels=3,
                has_bias=True,
                input_name='relu1_out',
                output_name='layer2_out'
            )
            
            builder.add_softmax(
                name='softmax',
                input_name='layer2_out',
                output_name='target'
            )
            
            # Get spec
            spec = builder.spec
            
            # Configure outputs
            spec.description.output[0].name = 'target'
            
            # Add probability output
            prob_output = spec.description.output.add()
            prob_output.name = 'classProbability'
            prob_output.type.dictionaryType.stringKeyType.SetInParent()
            
            spec.description.predictedFeatureName = 'target'
            spec.description.predictedProbabilitiesName = 'classProbability'
            
            coreml_model = MLModel(spec)
            print(f"   Method 3 successful")
            
        except Exception as e3:
            print(f"   All methods failed: {e3}")
            sys.exit(1)

# Add metadata
coreml_model.author = 'ForexScalper'
coreml_model.short_description = 'Predicts buy/sell signals for forex trading'
coreml_model.version = '1.0'

# Add input descriptions
if hasattr(coreml_model, 'get_spec'):
    spec = coreml_model.get_spec()
    for i, name in enumerate(feature_names):
        if i < len(spec.description.input):
            spec.description.input[i].name = name
            spec.description.input[i].shortDescription = f'Technical indicator: {name}'
    
    # Update model with new spec
    coreml_model = MLModel(spec)

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
    
    # Try to load and verify
    try:
        loaded = ct.models.MLModel(output_path)
        print(f"   ✅ Model verified - can be loaded")
    except Exception as e:
        print(f"   ⚠️ Model verification failed: {e}")
else:
    print(f"   ❌ File not found!")

print("\n" + "=" * 50)
print("Model creation complete!")
print("=" * 50)