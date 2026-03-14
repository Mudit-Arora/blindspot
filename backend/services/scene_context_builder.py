"""
Builds a human-readable scene context string from the structured
scene description JSON sent by the iOS app.
"""

import logging

logger = logging.getLogger("blindspot.scene_context")


class SceneContextBuilder:

    # Objects that are navigation hazards get flagged with priority
    HAZARD_LABELS = {
        "pothole", "construction", "construction cone",
        "stairs", "stairway", "vehicle", "car", "truck",
        "bus", "bicycle", "motorcycle", "fire hydrant",
        "pole", "barrier", "curb",
    }

    def build_context(self, scene_data: dict) -> str:
        """
        Convert a scene description dict into a text summary for the LLM.

        Expected input:
        {
            "objects": [
                {"label": "pothole", "position": "center", "distance": "5 feet", "confidence": 0.87},
                {"label": "person", "position": "left"},
                ...
            ]
        }
        """
        objects = scene_data.get("objects", [])

        if not objects:
            return "No objects detected in the scene."

        hazards = []
        non_hazards = []

        for obj in objects:
            label = obj.get("label", "unknown object")
            position = obj.get("position", "ahead")
            distance = obj.get("distance")
            confidence = obj.get("confidence", 0)

            desc = f"{label} on the {position}"
            if distance:
                desc += f", approximately {distance} away"

            if label.lower() in self.HAZARD_LABELS:
                hazards.append(desc)
            else:
                non_hazards.append(desc)

        parts = []

        if hazards:
            parts.append("HAZARDS DETECTED:")
            for h in hazards:
                parts.append(f"  - {h}")

        if non_hazards:
            if hazards:
                parts.append("")
            parts.append("Other objects:")
            for n in non_hazards:
                parts.append(f"  - {n}")

        context = "\n".join(parts)
        logger.info(f"Built scene context:\n{context}")
        return context

    def build_context_oneliner(self, scene_data: dict) -> str:
        """Compact single-line version for logging."""
        objects = scene_data.get("objects", [])
        if not objects:
            return "empty scene"
        return ", ".join(
            f"{o.get('label', '?')}({o.get('position', '?')})"
            for o in objects
        )
