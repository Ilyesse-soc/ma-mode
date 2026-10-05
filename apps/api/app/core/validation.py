"""Reject unknown properties and bound textual data, including nested lists."""

import unicodedata

from pydantic import BaseModel, ConfigDict, field_validator


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    @field_validator("*", mode="before")
    @classmethod
    def safe_text(cls, value):
        def check(item):
            if isinstance(item, str):
                if len(item) > 2048 or any(
                    unicodedata.category(c) == "Cc" and c not in "\n\r\t" for c in item
                ):
                    raise ValueError("Invalid text")
            elif isinstance(item, list):
                if len(item) > 100:
                    raise ValueError("Too many entries")
                for entry in item:
                    check(entry)

        check(value)
        return value
