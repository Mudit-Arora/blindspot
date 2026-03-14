"""
Audio format utilities for the Blindspot backend.
"""

import struct
import io
import logging

logger = logging.getLogger("blindspot.audio")


class AudioProcessor:
    """Utilities for audio format conversion and validation."""

    @staticmethod
    def validate_wav(data: bytes) -> bool:
        """Check if the data has a valid WAV header."""
        if len(data) < 44:
            return False
        return data[:4] == b"RIFF" and data[8:12] == b"WAVE"

    @staticmethod
    def get_wav_info(data: bytes) -> dict:
        """Extract WAV header metadata."""
        if len(data) < 44:
            return {}

        return {
            "format": struct.unpack_from("<H", data, 20)[0],
            "channels": struct.unpack_from("<H", data, 22)[0],
            "sample_rate": struct.unpack_from("<I", data, 24)[0],
            "byte_rate": struct.unpack_from("<I", data, 28)[0],
            "bits_per_sample": struct.unpack_from("<H", data, 34)[0],
            "data_size": struct.unpack_from("<I", data, 40)[0],
        }

    @staticmethod
    def pcm_to_wav(
        pcm_data: bytes,
        sample_rate: int = 16000,
        channels: int = 1,
        bits_per_sample: int = 16,
    ) -> bytes:
        """Wrap raw PCM data in a WAV header."""
        byte_rate = sample_rate * channels * (bits_per_sample // 8)
        block_align = channels * (bits_per_sample // 8)
        data_size = len(pcm_data)

        header = bytearray()
        header.extend(b"RIFF")
        header.extend(struct.pack("<I", 36 + data_size))
        header.extend(b"WAVE")
        header.extend(b"fmt ")
        header.extend(struct.pack("<I", 16))
        header.extend(struct.pack("<H", 1))              # PCM format
        header.extend(struct.pack("<H", channels))
        header.extend(struct.pack("<I", sample_rate))
        header.extend(struct.pack("<I", byte_rate))
        header.extend(struct.pack("<H", block_align))
        header.extend(struct.pack("<H", bits_per_sample))
        header.extend(b"data")
        header.extend(struct.pack("<I", data_size))
        header.extend(pcm_data)

        return bytes(header)

    @staticmethod
    def extract_pcm_from_wav(wav_data: bytes) -> bytes:
        """Strip the WAV header and return raw PCM data."""
        if not AudioProcessor.validate_wav(wav_data):
            return wav_data

        # Find the 'data' chunk
        offset = 12
        while offset < len(wav_data) - 8:
            chunk_id = wav_data[offset : offset + 4]
            chunk_size = struct.unpack_from("<I", wav_data, offset + 4)[0]
            if chunk_id == b"data":
                return wav_data[offset + 8 : offset + 8 + chunk_size]
            offset += 8 + chunk_size

        return wav_data[44:]

    @staticmethod
    def resample_simple(
        pcm_data: bytes,
        from_rate: int,
        to_rate: int,
        bits_per_sample: int = 16,
    ) -> bytes:
        """
        Nearest-neighbor resample — simple but functional.
        For production, use librosa or scipy for proper resampling.
        """
        if from_rate == to_rate:
            return pcm_data

        bytes_per_sample = bits_per_sample // 8
        num_samples = len(pcm_data) // bytes_per_sample
        ratio = to_rate / from_rate
        new_num_samples = int(num_samples * ratio)

        result = bytearray()
        for i in range(new_num_samples):
            src_idx = int(i / ratio)
            src_idx = min(src_idx, num_samples - 1)
            start = src_idx * bytes_per_sample
            end = start + bytes_per_sample
            result.extend(pcm_data[start:end])

        return bytes(result)
