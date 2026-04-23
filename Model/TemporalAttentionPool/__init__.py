import torch
import torch.nn as nn
import torch.nn.functional as F

class TemporalAttentionPool(nn.Module):
    """
    Temporal Attention Pooling
    Instead of averaging all time steps equally, learn a score per time step and take a weighted sum. Steps with more discriminative RR patterns get higher weight.
    
    Input:  [B, C, L]
    Output: [B, C]

    """
    def __init__(self, channels: int, dropout: float = 0.1):
        super().__init__()
        self.attention_conv = nn.Sequential(
            nn.Conv1d(channels, 1, kernel_size=1),
            nn.Dropout(dropout),
        )
        self.softmax = nn.Softmax(dim=-1)
        self.dropout = nn.Dropout(dropout)
    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        x: [B, C, L]
        output: [B, C]
        """
        scores = self.attention_conv(x)          # [B, 1, L]
        weights = self.softmax(scores)          # [B, 1, L]
        weights = self.dropout(weights)
        pooled = (x * weights).sum(dim=-1)      # [B, C]
        return pooled


