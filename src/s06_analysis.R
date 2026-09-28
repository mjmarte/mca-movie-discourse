suppressPackageStartupMessages({
  library(psych); library(ppcor); library(glmnet); library(pROC)
  library(effectsize); library(data.table); library(tidyverse)
})
select <- dplyr::select; filter <- dplyr::filter; mutate <- dplyr::mutate
summarise <- dplyr::summarise; arrange <- dplyr::arrange; rename <- dplyr::rename

HERE <- local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) return(dirname(normalizePath(f)))
  for (i in rev(seq_len(sys.nframe()))) {
    of <- sys.frame(i)$ofile
    if (!is.null(of)) return(dirname(normalizePath(of)))
  }
  normalizePath(".")
})
source(file.path(HERE, "config.R"))
RDIR <- data_root()
IN   <- file.path(RDIR, "features_rescored.csv")
OUT  <- TABLES
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

VARIANCE_THRESHOLD <- 1e-10
set.seed(SEED)

cat("================================================================\n")
cat(sprintf("input: %s\n", IN))
cat("================================================================\n")

df <- fread(IN)
stopifnot(all(df$Group %in% c("HC", "PWA")))
cat(sprintf("rows %d | HC %d participants | PWA %d participants\n", nrow(df),
            uniqueN(df[Group == "HC"]$Participant), uniqueN(df[Group == "PWA"]$Participant)))

metadata_cols <- c("Participant", "Group", "Clip", "filename", "group_binary")
mc_features    <- grep("^mc_", names(df), value = TRUE)
other_features <- setdiff(names(df)[sapply(df, is.numeric)], c(mc_features, "group_binary"))
all_features   <- c(other_features, mc_features)

all_features <- setdiff(all_features, all_features[grepl("_max$|_min$|_stdev$", all_features)])

all_features <- setdiff(all_features, "mattr")
feature_data <- df %>% select(all_of(all_features))
valid <- sapply(feature_data, function(x) is.numeric(x) && sum(!is.na(x)) > 10 &&
                                          var(x, na.rm = TRUE) > VARIANCE_THRESHOLD)
all_features <- all_features[valid]
feature_data <- feature_data %>% select(all_of(all_features))
cat(sprintf("features entering the correlation filter: %d\n", length(all_features)))

cor_matrix <- cor(feature_data, use = "pairwise.complete.obs")
cu <- cor_matrix; cu[lower.tri(cu, diag = TRUE)] <- NA
hp <- which(abs(cu) > CORR_THRESHOLD, arr.ind = TRUE)
removed <- character(0)
if (nrow(hp) > 0) {
  pairs_df <- data.frame(feature1 = rownames(cor_matrix)[hp[, 1]],
                         feature2 = colnames(cor_matrix)[hp[, 2]],
                         correlation = cor_matrix[hp]) %>% arrange(desc(abs(correlation)))
  removed <- unique(pairs_df$feature2)
  fwrite(pairs_df, file.path(OUT, "high_correlation_pairs.csv"))
}
kept <- setdiff(all_features, removed)
cat(sprintf("retained after filter: %d  (MC %d)\n", length(kept), sum(grepl("^mc_", kept))))
writeLines(kept, file.path(OUT, "retained_features.txt"))

df <- df %>% mutate(across(all_of(kept), ~ as.numeric(scale(.))))
fwrite(df %>% select(all_of(intersect(c(metadata_cols, kept), names(df)))),
       file.path(OUT, "preprocessed_data.csv"))

dem <- fread(file.path(RDIR, "demographics.csv")) %>% select(Participant, Age)
aq  <- fread(file.path(RDIR, "aphasia_quotient.csv"))
aq_col <- intersect(c("AQ", "aq", "WAB_AQ", "AQ_score"), names(aq))[1]
aq <- aq %>% select(Participant, aq_score = all_of(aq_col))

agg <- df %>% group_by(Participant, Group) %>%
  summarise(across(all_of(kept), ~ mean(.x, na.rm = TRUE)), .groups = "drop") %>%
  left_join(dem, by = "Participant") %>% left_join(aq, by = "Participant")
fwrite(agg, file.path(OUT, "participant_level.csv"))
cat(sprintf("participant-level rows: %d\n", nrow(agg)))

tab1 <- map_dfr(kept, function(f) {
  hc <- agg %>% filter(Group == "HC")  %>% pull(f)
  pw <- agg %>% filter(Group == "PWA") %>% pull(f)
  d  <- cohens_d(pw, hc, na.rm = TRUE)$Cohens_d
  fit <- aov(as.formula(sprintf("`%s` ~ Age + Group", f)), data = agg)
  p  <- summary(fit)[[1]]["Group", "Pr(>F)"]
  tibble(feature = f, hc_m = mean(hc, na.rm = TRUE), hc_sd = sd(hc, na.rm = TRUE),
         pwa_m = mean(pw, na.rm = TRUE), pwa_sd = sd(pw, na.rm = TRUE),
         cohens_d = d, p_ancova = p)
}) %>% mutate(p_fdr = p.adjust(p_ancova, method = "fdr"))
fwrite(tab1, file.path(OUT, "table1_group_differences.csv"))
cat("\n-- Table 1 (macrolinguistic rows) --\n")
print(tab1 %>% filter(grepl("^mc_|sentiment", feature)) %>%
        select(feature, hc_m, hc_sd, pwa_m, pwa_sd, cohens_d, p_fdr) %>%
        mutate(across(where(is.numeric), ~ round(.x, 4))) %>% as.data.frame())

macro <- kept[grepl("^mc_|sentiment_rating", kept)]
micro <- setdiff(kept, macro)
calc_d <- function(dat, fs) sapply(fs, function(f) {
  a <- dat %>% filter(Group == "PWA") %>% pull(f); b <- dat %>% filter(Group == "HC") %>% pull(f)
  if (length(a) < 2 || length(b) < 2) return(NA_real_)
  cohens_d(a, b, na.rm = TRUE)$Cohens_d
})
obs_macro <- mean(abs(calc_d(agg, macro)), na.rm = TRUE)
obs_micro <- mean(abs(calc_d(agg, micro)), na.rm = TRUE)
obs_diff  <- obs_macro - obs_micro

set.seed(42)
pwa_ids <- agg$Participant[agg$Group == "PWA"]; hc_ids <- agg$Participant[agg$Group == "HC"]
boot_diffs <- replicate(2000, {
  bd <- bind_rows(agg[match(sample(pwa_ids, length(pwa_ids), TRUE), agg$Participant), ],
                  agg[match(sample(hc_ids,  length(hc_ids),  TRUE), agg$Participant), ])
  mean(abs(calc_d(bd, macro)), na.rm = TRUE) - mean(abs(calc_d(bd, micro)), na.rm = TRUE)
})
set.seed(42)
all_f <- c(macro, micro)
observed_all <- abs(calc_d(agg, all_f)); names(observed_all) <- all_f
perm_diffs <- replicate(10000, {
  idx <- sample(length(all_f))
  fm <- all_f[idx[seq_along(macro)]]; fi <- all_f[idx[-seq_along(macro)]]
  mean(observed_all[fm], na.rm = TRUE) - mean(observed_all[fi], na.rm = TRUE)
}, simplify = TRUE)
boot_ci <- quantile(boot_diffs, c(0.025, 0.975))
perm_p  <- mean(abs(perm_diffs) >= abs(obs_diff))
cat(sprintf("\n-- macro vs micro --\n  macro mean|d| %.3f | micro mean|d| %.3f | diff %.3f\n  95%% CI [%.3f, %.3f] | permutation p = %.4f\n",
            obs_macro, obs_micro, obs_diff, boot_ci[1], boot_ci[2], perm_p))
fwrite(tibble(macro_mean_abs_d = obs_macro, micro_mean_abs_d = obs_micro, difference = obs_diff,
              ci_lo = boot_ci[1], ci_hi = boot_ci[2], perm_p = perm_p,
              n_boot = 2000, n_perm = 10000),
       file.path(OUT, "macro_vs_micro_bootstrap.csv"))

pw <- agg %>% filter(Group == "PWA", !is.na(aq_score), !is.na(Age))
cat(sprintf("\nPWA with AQ and age: %d\n", nrow(pw)))
tab2 <- map_dfr(kept, function(f) {
  sub <- pw %>% select(v = all_of(f), aq_score, Age) %>% drop_na()
  pc <- pcor.test(sub$v, sub$aq_score, sub$Age)
  z  <- atanh(pc$estimate); se <- 1 / sqrt(nrow(sub) - 3 - 1)
  tibble(feature = f, n = nrow(sub), partial_r = pc$estimate, p_value = pc$p.value,
         ci_lo = tanh(z - 1.96 * se), ci_hi = tanh(z + 1.96 * se))
}) %>% mutate(p_fdr = p.adjust(p_value, method = "fdr")) %>% arrange(desc(abs(partial_r)))
fwrite(tab2, file.path(OUT, "table2_aq_partial_correlations.csv"))
cat("\n-- Table 2 (top rows) --\n")
print(tab2 %>% mutate(across(where(is.numeric), ~ round(.x, 4))) %>% head(8) %>% as.data.frame())

lasso_dat <- agg %>% select(Participant, Group, all_of(kept)) %>% drop_na(all_of(kept))
X <- as.matrix(lasso_dat %>% select(all_of(kept)))
y <- as.numeric(lasso_dat$Group == "PWA")
pwa_i <- which(y == 1); hc_i <- which(y == 0)
folds <- expand.grid(p = pwa_i, h = hc_i)
n_folds <- nrow(folds)
cat(sprintf("\nLTOCV folds: %d (n = %d)\n", n_folds, nrow(X)))

pred_sum <- numeric(nrow(X)); pred_n <- numeric(nrow(X))
sel_count <- setNames(numeric(length(kept)), kept)
set.seed(42)
for (i in seq_len(n_folds)) {
  te <- c(folds$p[i], folds$h[i]); tr <- setdiff(seq_len(nrow(X)), te)
  cvf <- cv.glmnet(X[tr, ], y[tr], family = "binomial", alpha = 1, nfolds = 5,
                   type.measure = "auc")
  pp <- predict(cvf, newx = X[te, , drop = FALSE], s = "lambda.min", type = "response")[, 1]
  pred_sum[te] <- pred_sum[te] + pp; pred_n[te] <- pred_n[te] + 1
  co <- as.matrix(coef(cvf, s = "lambda.min"))[-1, 1]
  sel_count[names(co)[co != 0]] <- sel_count[names(co)[co != 0]] + 1
  if (i %% 250 == 0) cat(sprintf("  fold %d/%d\n", i, n_folds))
}
pred <- pred_sum / pred_n
roc_obj <- roc(y, pred, quiet = TRUE)
best <- coords(roc_obj, "best", best.method = "youden", ret = c("threshold", "sensitivity", "specificity"))
thr <- as.numeric(best["threshold"][1, 1])
cls <- as.numeric(pred >= 0.5)
acc <- mean(cls == y); sens <- sum(cls == 1 & y == 1) / sum(y == 1); spec <- sum(cls == 0 & y == 0) / sum(y == 0)
perf <- tibble(auc = as.numeric(auc(roc_obj)), accuracy = acc, sensitivity = sens,
               specificity = spec, youden_j = sens + spec - 1,
               youden_thresh_sens = as.numeric(best["sensitivity"][1, 1]),
               youden_thresh_spec = as.numeric(best["specificity"][1, 1]),
               youden_j_at_best = as.numeric(best["sensitivity"][1, 1]) +
                                  as.numeric(best["specificity"][1, 1]) - 1,
               n_folds = n_folds, n = nrow(X))
print(as.data.frame(perf))
fwrite(perf, file.path(OUT, "lasso_performance.csv"))
fwrite(tibble(Participant = lasso_dat$Participant, Group = lasso_dat$Group,
              true = y, pred_prob = pred, pred_class = cls),
       file.path(OUT, "lasso_predictions.csv"))

set.seed(42)
lam_grid <- glmnet(X, y, family = "binomial", alpha = 1)$lambda
cvm_mat <- matrix(NA_real_, nrow = 100, ncol = length(lam_grid))
for (r in 1:100) {
  cvr <- cv.glmnet(X, y, family = "binomial", alpha = 1, nfolds = 5,
                   type.measure = "auc", lambda = lam_grid)
  cvm_mat[r, ] <- cvr$cvm
}
mean_cvm <- colMeans(cvm_mat, na.rm = TRUE)
lambda_opt <- lam_grid[which.max(mean_cvm)]
cat(sprintf("final-refit lambda (100 repeated 5-fold CV): %.5f  (mean CV AUC %.4f)\n",
            lambda_opt, max(mean_cvm)))
final_fit <- glmnet(X, y, family = "binomial", alpha = 1, lambda = lam_grid)
fc <- as.matrix(coef(final_fit, s = lambda_opt))[-1, 1]
fwrite(tibble(lambda = lam_grid, mean_cv_auc = mean_cvm), file.path(OUT, "lasso_lambda_curve.csv"))
stab <- tibble(feature = kept, coefficient = fc[kept],
               selection_pct = 100 * sel_count[kept] / n_folds) %>%
  arrange(desc(abs(coefficient)))
fwrite(stab, file.path(OUT, "lasso_coefficients_stability.csv"))
cat(sprintf("\nnon-zero at optimal lambda: %d | stable (>=80%%): %d\n",
            sum(stab$coefficient != 0), sum(stab$selection_pct >= 80)))
print(as.data.frame(stab %>% mutate(across(where(is.numeric), ~ round(.x, 4)))))

pca_in <- agg %>% select(all_of(kept)) %>% drop_na()
pc_raw <- principal(pca_in, nfactors = 8, rotate = "varimax")
ev <- eigen(cor(pca_in))$values
fwrite(tibble(PC = paste0("PC", 1:8), eigenvalue = ev[1:8],
              variance_pct = 100 * ev[1:8] / length(kept),
              cumulative_pct = cumsum(100 * ev[1:8] / length(kept))),
       file.path(OUT, "pca_variance.csv"))
fwrite(as.data.frame(unclass(pc_raw$loadings)) %>% rownames_to_column("feature"),
       file.path(OUT, "pca_loadings.csv"))

perclip <- df %>% pivot_longer(all_of(kept), names_to = "feature", values_to = "v") %>%
  group_by(Clip, feature) %>%
  summarise(d = tryCatch(cohens_d(v[Group == "PWA"], v[Group == "HC"], na.rm = TRUE)$Cohens_d,
                         error = function(e) NA_real_),
            n_hc = sum(Group == "HC" & !is.na(v)), n_pwa = sum(Group == "PWA" & !is.na(v)),
            .groups = "drop")
fwrite(perclip, file.path(OUT, "per_clip_effect_sizes.csv"))

cat(sprintf("\ndone -> %s\n", OUT))
