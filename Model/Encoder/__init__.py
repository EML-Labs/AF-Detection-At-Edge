
import torch
from torch import nn
import torch.nn.functional as F
from Model.TemporalAttentionPool import TemporalAttentionPool

class Encoder(nn.Module):
    def __init__(self, latent_dim:int,dropout:float=0.1):
        super().__init__()
        self.branch1 = nn.Sequential(
            nn.Conv1d(1, 16, kernel_size=3, stride=2, padding=1), # [B, 16, window_size/2]
            nn.GroupNorm(num_groups=8, num_channels=16),
            nn.ReLU(),
            nn.Conv1d(16, 32, kernel_size=3, stride=2, padding=1), # [B, 32, window_size/4]
            nn.GroupNorm(num_groups=8, num_channels=32),
            nn.ReLU(),
            nn.Conv1d(32, 64, kernel_size=3, stride=2, padding=1), # [B, 64, window_size/4]
            nn.GroupNorm(num_groups=8, num_channels=64),
            nn.ReLU(),
        )

        self.branch2 = nn.Sequential(
            nn.Conv1d(1, 16, kernel_size=5, stride=2, padding=2), # [B, 16, window_size/2]
            nn.GroupNorm(num_groups=8, num_channels=16),
            nn.ReLU(),
            nn.Conv1d(16, 32, kernel_size=5, stride=2, padding=2), # [B, 32, window_size/4]
            nn.GroupNorm(num_groups=8, num_channels=32),
            nn.ReLU(),
            nn.Conv1d(32, 64, kernel_size=5, stride=2, padding=2), # [B, 64, window_size/4]
            nn.GroupNorm(num_groups=8, num_channels=64),
            nn.ReLU(),
        )

        self.branch3 = nn.Sequential(
            nn.Conv1d(1, 16, kernel_size=7, stride=2, padding=3), # [B, 16, window_size/2]
            nn.GroupNorm(num_groups=8, num_channels=16),
            nn.ReLU(),
            nn.Conv1d(16, 32, kernel_size=7, stride=2, padding=3), # [B, 32, window_size/4]
            nn.GroupNorm(num_groups=8, num_channels=32),
            nn.ReLU(),
            nn.Conv1d(32, 64, kernel_size=7, stride=2, padding=3), # [B, 64, window_size/4]
            nn.GroupNorm(num_groups=8, num_channels=64),
            nn.ReLU(),
        )

        self.channel_mix = nn.Sequential(
            nn.Conv1d(3*64,3*64, kernel_size=1),
            nn.GroupNorm(num_groups=8, num_channels=3*64),
            nn.ReLU(),
            nn.Dropout(dropout),
        )
        self.attention_pool = TemporalAttentionPool(3*64, dropout=dropout)
        self.proj = nn.Sequential(
            nn.Linear(3*64, latent_dim),
            nn.Dropout(dropout),
        )

    def forward(self, rr_window)->torch.Tensor:
        """
        rr_window: [B, window_size]
        output:    [B, LATENT_SIZE]
        """

        rr_window = rr_window.unsqueeze(1) # [B, 1, window_size]

        x1 = self.branch1(rr_window)  # [B, 64, window_size/4]
        x2 = self.branch2(rr_window)  # [B, 64, window_size/4]
        x3 = self.branch3(rr_window)  # [B, 64, window_size/4]
        x = torch.cat([x1, x2, x3], dim=1)  # [B, 3*64, window_size/4]
        x = self.channel_mix(x)  # [B, 3*64, window_size/4]
        x = self.attention_pool(x)  # [B, 3*64]
        x = self.proj(x)  # [B, latent_dim]
        return x
