import tensorflow as tf
import coremltools as ct

# 1) Load or define your Keras model
# Example simple model:
inputs = tf.keras.Input(shape=(224, 224, 3), name="input")  # NHWC
x = tf.keras.layers.Flatten()(inputs)
x = tf.keras.layers.Dense(64, activation="relu")(x)
outputs = tf.keras.layers.Dense(3, name="scores")(x)       # scores tensor
keras_model = tf.keras.Model(inputs=inputs, outputs=outputs)
keras_model.summary()

# 2) Create classifier config if desired (optional)
labels_path = "labels.txt"  # must exist if you enable classifier_config
classifier_config = ct.ClassifierConfig(class_labels=labels_path)

# 3) Convert to Core ML
# Note: specify input shape as a TensorType; Core ML will treat outputs as MLMultiArray by default
mlmodel = ct.convert(
    keras_model,
    inputs=[
        ct.TensorType(
            name="input",
            shape=(1, 224, 224, 3),  # batch 1, NHWC
            dtype=tf.float32
        )
    ],
    outputs=[ct.TensorType(name="scores")],
    classifier_config=classifier_config,        # optional; can be None
    minimum_deployment_target=ct.target.iOS17,
)

# 4) Save the model
mlmodel.save("TradingModel.mlmodel")
print("Saved TradingModel.mlmodel")