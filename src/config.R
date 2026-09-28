.config_dir <- local({
  for (i in rev(seq_len(sys.nframe()))) {
    of <- sys.frame(i)$ofile
    if (!is.null(of)) return(dirname(normalizePath(of)))
  }
  normalizePath(".")
})

REPO   <- normalizePath(file.path(.config_dir, ".."), mustWork = FALSE)
TABLES <- file.path(REPO, "results", "tables")

FIGURES <- file.path(REPO, "manuscript", "figures")

data_root <- function() {
  root <- Sys.getenv("MCA_DATA", unset = "")
  if (!nzchar(root)) {
    stop("MCA_DATA is not set. This step reads the restricted study data, which is not ",
         "distributed with this repository. See README.md.", call. = FALSE)
  }
  if (!dir.exists(root)) stop("MCA_DATA points at ", root, ", which is not a directory.", call. = FALSE)
  normalizePath(root)
}

CLIPS <- c("CMIYC", "PC", "PT", "MOON", "AKB", "MIR", "GWH", "NCOM")

CLIP_SHORT <- c(AKB = "Akeelah", CMIYC = "Catch Me", GWH = "Good Will", MIR = "Miracle",
                MOON = "Moonlight", NCOM = "No Country", PT = "Parent Trap",
                PC = "Partly Cloudy")

FEATURE_LABELS <- c(
  mc_coverage_percentage       = "MC completeness",
  mc_avg_distance_to_centroid  = "MC distance to centroid",
  mc_semantic_coherence        = "MC semantic coherence",
  sentiment_rating             = "Sentiment rating",
  disfluencies_per_100_words   = "Disfluency rate",
  total_filled_pauses          = "Nonverbal utterances count",
  word_count                   = "Word count",
  mlu_morphemes                = "MLU morphemes",
  honore_statistic             = "Honore's statistic",
  frequency_range              = "Frequency range",
  high_freq_word_ratio         = "High-frequency word ratio",
  mean_log_frequency           = "Mean log frequency",
  mean_content_word_frequency  = "Mean content word frequency",
  content_word_ratio           = "Content word ratio",
  clauses_per_sentence         = "Clauses per sentence",
  noun_ratio                   = "Noun ratio",
  adv_ratio                    = "Adverb ratio",
  adj_ratio                    = "Adjective ratio",
  verb_ratio                   = "Verb ratio"
)

CORR_THRESHOLD <- 0.60

LAMBDA_OPT <- 0.00904

SEED <- 42
