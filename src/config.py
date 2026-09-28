import os
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TABLES = REPO / "results" / "tables"
FIGURES = REPO / "manuscript" / "figures"

def generation_runs() -> Path:
    root = os.environ.get("MCA_GENERATION_RUNS")
    if not root:
        raise SystemExit("MCA_GENERATION_RUNS is not set. See README.md.")
    return Path(root).expanduser().resolve()

def data_root() -> Path:
    root = os.environ.get("MCA_DATA")
    if not root:
        raise SystemExit(
            "MCA_DATA is not set. This step reads the restricted study data, which is not "
            "distributed with this repository. See README.md."
        )
    path = Path(root).expanduser().resolve()
    if not path.is_dir():
        raise SystemExit(f"MCA_DATA points at {path}, which is not a directory.")
    return path

CLIPS = ["CMIYC", "PC", "PT", "MOON", "AKB", "MIR", "GWH", "NCOM"]

CLIP_TITLES = {
    "AKB": "Akeelah and the Bee",
    "CMIYC": "Catch Me If You Can",
    "GWH": "Good Will Hunting",
    "MIR": "Miracle",
    "MOON": "Moonlight",
    "NCOM": "No Country for Old Men",
    "PT": "The Parent Trap",
    "PC": "Partly Cloudy",
}

CLIP_SHORT = {
    "AKB": "Akeelah",
    "CMIYC": "Catch Me",
    "GWH": "Good Will",
    "MIR": "Miracle",
    "MOON": "Moonlight",
    "NCOM": "No Country",
    "PT": "Parent Trap",
    "PC": "Partly Cloudy",
}

CLIP_KEY = {"akeelah": "AKB", "catchme": "CMIYC", "goodwill": "GWH", "miracle": "MIR",
            "moonlight": "MOON", "nocountry": "NCOM", "parenttrap": "PT",
            "partlycloudy": "PC"}

CLIP_MAP = {"AKB": "AkeelahAndTheBee", "CMIYC": "CatchMeIfYouCan", "GWH": "GoodWillHunting",
            "MIR": "Miracle", "MOON": "Moonlight", "NCOM": "NoCountryForOldMen",
            "PT": "ParentTrap", "PC": "PartlyCloudy"}

MATCH_THRESHOLD = 0.50

CONCEPT_EQUIVALENCE_REPORTED = 0.63

MIN_RUN_SUPPORT = 3

HC_PRODUCTION_FLOOR = 0.20

SEED = 42
