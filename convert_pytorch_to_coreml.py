import torch
import coremltools as ct

# 1) Load your trained PyTorch model
# Replace with your actual model load
# Example:
#   from my_model_def import MyNet
#   model = MyNet()
#   model.load_state_dict(torch.load("weights.pth", map_location="cpu"))
#   model.eval()
#
# For illustration, a simple model:
class TinyNet(torch.nn.Module):
    def __init__(self, num_classes=3):
        super().__init__()
        self.net = torch.nn.Sequential(
            torch.nn.Flatten(),
            torch.nn.Linear(3 * 224 * 224, 64),
            torch.nn.ReLU(),
            torch.nn.Linear(64, num_classes),
        )
    def forward(self, x):
        return self.net(x)

num_classes = 3
model = TinyNet(num_classes=num_classes).eval()

# 2) Example input shape: NCHW (1, 3, 224, 224)
example_input = torch.randn(1, 3, 224, 224)

# 3) Trace or script the model
traced = torch.jit.trace(model, example_input)

# 4) Create a classifier config if you want label mapping (optional)
# If not needed, set classifier_config=None
labels_path = "labels.txt"  # must exist if you enable classifier_config
classifier_config = ct.ClassifierConfig(class_labels=labels_path)

# 5) Convert to Core ML
mlmodel = ct.convert(
    traced,
    inputs=[
        ct.TensorType(
            name="input",
            shape=example_input.shape,          # (1, 3, 224, 224)
            dtype=torch.float32
        )
    ],
    outputs=[ct.TensorType(name="scores")],     # tensor output (MLMultiArray)
    classifier_config=classifier_config,        # optional; provides classifier interface
    minimum_deployment_target=ct.target.iOS17,  # adjust to your deployment
)

# 6) Save the model
mlmodel.save("TradingModel.mlmodel")
print("Saved TradingModel.mlmodel")