import torch
from torch import nn

class Classifier(nn.Module):
    def __init__(self, latent_dim:int, dropout:float=0.1):
        super().__init__()
        self.classifier = nn.Sequential(
        nn.Linear(latent_dim, 1)
        )

    def forward(self, x:torch.Tensor)->torch.Tensor:
        """
        x: [B, latent_dim]
        output: [B, 1] logits (use with BCEWithLogitsLoss)
        """
        return self.classifier(x)