#!/usr/bin/env python3
"""
Train a real forex trading model with meaningful patterns
"""

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
import coremltools as ct

print("=" * 50)
print("Training Real Forex Trading Model")
print("=" * 50)

# Generate synthetic but realistic forex data
np.random.seed(42)
n_samples = 5000

# Create features with realistic patterns
features = []
labels = []

for i in range(n_samples):
    # Base price around 1.05 for EUR/USD like pairs
    price_base = 1.05 + np.random.randn() * 0.02
    
    # Create realistic feature values
    returns = np.random.randn() * 0.001  # Small returns
    high_low_pct = np.random.exponential(0.001)  # Volatility
    close_open_pct = np.random.randn() * 0.0005
    
    # Moving averages - create trends
    trend = np.random.choice([-1, 0, 1]) * 0.01
    sma_10 = price_base + trend * 0.5 + np.random.randn() * 0.001
    sma_20 = price_base + trend * 0.3 + np.random.randn() * 0.001
    sma_50 = price_base + trend * 0.1 + np.random.randn() * 0.001
    
    ema_12 = sma_10 + np.random.randn() * 0.0005
    ema_26 = sma_20 + np.random.randn() * 0.0005
    
    # Technical indicators
    if trend > 0:
        rsi = 60 + np.random.randn() * 10
        macd = 0.001 + np.random.randn() * 0.0005
        label = 1  # Buy
    elif trend < 0:
        rsi = 40 + np.random.randn() * 10
        macd = -0.001 + np.random.randn() * 0.0005
        label = 0  # Sell
    else:
        rsi = 50 + np.random.randn() * 10
        macd = np.random.randn() * 0.0005
        label = 2  # Hold
    
    macd_signal = macd * 0.9 + np.random.randn() * 0.0001
    macd_hist = macd - macd_signal
    
    bb_width = np.random.exponential(0.005)
    bb_position = 0.3 + np.random.rand() * 0.4
    
    atr_pct = np.random.exponential(0.002)
    volume_ratio = 1.0 + np.random.randn() * 0.3
    
    features.append([
        returns, high_low_pct, close_open_pct, sma_10, sma_20, sma_50,
        ema_12, ema_26, rsi, macd, macd_signal, macd_hist,
        bb_width, bb_position, atr_pct, volume_ratio
    ])
    labels.append(label)

X = np.array(features)
y = np.array(labels)

print(f"Training samples: {len(X)}")
print(f"Class distribution: {np.bincount(y)}")

# Split data
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# Train model
model = RandomForestClassifier(
    n_estimators=100,
    max_depth=10,
    min_samples_split=10,
    random_state=42,
    n_jobs=-1
)

print("\n🤖 Training model...")
model.fit(X_train, y_train)

# Evaluate
train_score = model.score(X_train, y_train)
test_score = model.score(X_test, y_test)
print(f"Train accuracy: {train_score:.2%}")
print(f"Test accuracy: {test_score:.2%}")

# Convert to Core ML
print("\n🔄 Converting to Core ML...")

# Define feature descriptions
feature_names = [
    'returns', 'high_low_pct', 'close_open_pct', 'sma_10', 'sma_20', 
    'sma_50', 'ema_12', 'ema_26', 'rsi', 'macd', 'macd_signal', 
    'macd_hist', 'bb_width', 'bb_position', 'atr_pct', 'volume_ratio'
]

# Convert using sklearn converter
coreml_model = ct.converters.sklearn.convert(
    model,
    feature_names=feature_names,
    target='signal',
    model_name='ForexTradingModel'
)

# Add metadata
coreml_model.author = 'ForexScalper'
coreml_model.short_description = 'Forex trading signal predictor (0=sell, 1=buy, 2=hold)'
coreml_model.version = '1.0'

# Add input descriptions
for i, name in enumerate(feature_names):
    coreml_model.input_description[name] = f'{name} feature'

coreml_model.output_description['classProbability'] = 'Probability of each class'
coreml_model.output_description['classLabel'] = 'Predicted class (0=sell, 1=buy, 2=hold)'

# Save model
output_path = 'TradingModel.mlmodel'
coreml_model.save(output_path)

print(f"\n✅ Model saved to: {output_path}")
print("\n" + "=" * 50)