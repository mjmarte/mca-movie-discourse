# Assessing spoken discourse in aphasia using multimodal artificial intelligence

Analysis code for the paper.

- `prompts/`: inventory generation prompt (Gemini 2.5 Pro) and sentiment rating prompt (Gemma 3 12B; Girard et al., 2026).
- `src/`: analysis scripts, run in numbered order; `src/figures/` builds the figures.
- `results/tables/`: aggregate results reported in the paper.

## Running

```bash
pip install -r requirements.txt
Rscript -e 'install.packages(sub("\\s*#.*", "", readLines("r-packages.txt")))'
export MCA_DATA=/path/to/study/data
export MCA_GENERATION_RUNS=/path/to/generation/runs   # <clip>/<clip>_cand1..5.json

python src/s01_build_inventories.py
python src/s02_score_narrations.py
python src/s03_validate_inventories.py
python src/s04_project_embeddings.py
python src/s05_utterance_distances.py
Rscript src/s06_analysis.R
python src/s07_classification_ci.py
Rscript src/figures/build_all.R
```

## Data

Participant data are not included. Requests go to the corresponding author.

## Citation

Marte, M. J., Lee, S., Wang, S., Goldin, K., Varkanitsa, M., Girard, J. M., Brito, R.,
Wei, X., Baker, J. T., Tie, Y., Kiran, S., & Liebenthal, E. Assessing spoken discourse in
aphasia using multimodal artificial intelligence. *medRxiv* (2026).
