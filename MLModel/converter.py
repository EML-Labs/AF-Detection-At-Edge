import os
import torch
import coremltools as ct
from Model import Model

BASE_PATH = os.path.join(os.getcwd(),'Exports','models')
MODEL_PATH = os.path.join(BASE_PATH,'best_model.pth')
ENCODER_PATH = os.path.join(BASE_PATH,'encoder.pth')
MLPACKAGE_PATH = os.path.join(BASE_PATH,'encoder.mlpackage')

model = Model(
    latent_dim=128,
    projection_dim=64,
    dropout=0.1
)
model.load_state_dict(torch.load(MODEL_PATH))
encoder = model.encoder
encoder.eval()

example_input = torch.rand(1, 200)  # Adjust the shape based on your model's expected input
traced_model = torch.jit.trace(encoder, example_input)

mlmodel = ct.convert(
    traced_model,
    inputs=[ct.TensorType(name="rr_intervals_scaled", shape=example_input.shape)],
    minimum_deployment_target=ct.target.watchOS10
)

# 4. Save the converted model
mlmodel.save(MLPACKAGE_PATH)
torch.save(encoder.state_dict(), ENCODER_PATH)
