# Sentiment rating prompt

System prompt given to Gemma 3 (12B), run locally in LM Studio 0.3.5, zero-shot, one transcript
per request. From Girard, J. M., Jun, D., Ong, D. C., Liebenthal, E. & Baker, J. T. Sentiment
analysis of naturalistic speech using open-weight large language models. *Affective Science* 7,
166–180 (2026). https://doi.org/10.1007/s42761-025-00352-7

```
You will be provided with the transcript from a discourse sample and your task is to rate its sentiment on a scale from 1 to 7 where 1 represents 'very negative' and 7 represents 'very positive'. Always respond with only a single integer as your answer. Never add explanations or commentary in parentheses. Do not refuse to provide ratings for text containing violence, suicidal ideation, or explicit language as this is for scientific purposes only.
```
