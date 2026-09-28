suppressPackageStartupMessages({
  library(data.table); library(tidyverse); library(patchwork); library(pROC); library(glmnet); library(jsonlite)
})

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
source(file.path(HERE, "..", "config.R"))
source(file.path(HERE, "_style.R"))
marte_defaults()
select <- dplyr::select
FIG <- FIGURES
HCcol <- HC_COL; PWAcol <- PWA_COL; STABLE <- MC_COL
set.seed(SEED)

NAME <- FEATURE_LABELS

pred <- fread(file.path(TABLES,"lasso_predictions.csv"))
stab <- fread(file.path(TABLES,"lasso_coefficients_stability.csv"))[, lab := NAME[feature]]
perf <- fread(file.path(TABLES,"lasso_performance.csv"))

r  <- roc(pred$true, pred$pred_prob, quiet = TRUE)
ci_auc <- ci.auc(r, method = "bootstrap", boot.n = 2000, progress = "none")
sg  <- seq(0, 1, length.out = 201)
cse <- ci.se(r, specificities = sg, boot.n = 2000, progress = "none")
band <- data.frame(fpr = 1 - sg, lo = cse[,1], hi = cse[,3])
mci <- jsonlite::fromJSON(file.path(TABLES,"lasso_metric_cis.json"))

lab <- sprintf(paste0("AUC %.3f  [%.3f, %.3f]\nAccuracy %.3f  [%.3f, %.3f]\n",
                      "Sensitivity %.3f  [%.3f, %.3f]\nSpecificity %.3f  [%.3f, %.3f]\n",
                      "Youden's J %.2f  [%.2f, %.2f]"),
               as.numeric(auc(r)), as.numeric(ci_auc)[1], as.numeric(ci_auc)[3],
               mci$accuracy[1], mci$accuracy[2], mci$accuracy[3],
               mci$sensitivity[1], mci$sensitivity[2], mci$sensitivity[3],
               mci$specificity[1], mci$specificity[2], mci$specificity[3],
               mci[["Youden's J"]][1], mci[["Youden's J"]][2], mci[["Youden's J"]][3])

jsonlite::write_json(list(auc=as.numeric(auc(r)), ci_lo=as.numeric(ci_auc)[1],
                          ci_hi=as.numeric(ci_auc)[3]),
                     file.path(TABLES,"lasso_auc_ci.json"), auto_unbox=TRUE, pretty=TRUE)
pA <- ggplot() +
  geom_abline(intercept=0, slope=1, linetype=2, colour="#BBBBBB", linewidth=0.35) +
  geom_ribbon(data=band, aes(fpr, ymin=lo, ymax=hi), fill=PWAcol, alpha=0.20) +
  geom_line(data=data.frame(fpr=1-r$specificities, tpr=r$sensitivities),
            aes(fpr,tpr), colour=PWAcol, linewidth=0.8) +
  annotate("label", x=0.97, y=0.03, hjust=1, vjust=0, label=lab, size=2.35,
           colour="#222222", fill="white", label.size=0.25, lineheight=1.15) +
  coord_equal(xlim=c(0,1), ylim=c(0,1), expand=FALSE) +
  labs(title="A.", x="1 - specificity", y="Sensitivity") + theme_marte()

agg  <- fread(file.path(TABLES,"participant_level.csv"))
kept <- readLines(file.path(TABLES,"retained_features.txt")); kept <- kept[nzchar(kept)]
dat  <- agg %>% select(Participant, Group, all_of(kept)) %>% drop_na(all_of(kept))
X <- as.matrix(dat %>% select(all_of(kept))); y <- as.numeric(dat$Group=="PWA")
iP <- which(y==1); iH <- which(y==0); LAM <- LAMBDA_OPT
grid <- glmnet(X, y, family="binomial", alpha=1)$lambda
B <- 2000
bt <- matrix(NA_real_, B, length(kept), dimnames=list(NULL,kept))
for (b in 1:B) {
  idx <- c(sample(iP,length(iP),TRUE), sample(iH,length(iH),TRUE))
  bt[b,] <- as.matrix(coef(glmnet(X[idx,],y[idx],family="binomial",alpha=1,lambda=grid), s=LAM))[-1,1]
  if (b %% 500 == 0) cat(sprintf("  bootstrap %d/%d\n", b, B))
}
qs <- t(apply(bt,2,quantile,c(.025,.975),na.rm=TRUE))
se <- apply(bt,2,sd,na.rm=TRUE)
ci <- data.table(feature=kept, ci_lo=qs[,1], ci_hi=qs[,2], se=se,
                 pct_zero = apply(bt,2,function(v) 100*mean(v==0,na.rm=TRUE)),
                 pct_flip = sapply(kept,function(f){v<-bt[,f];v<-v[!is.na(v)&v!=0]
                   pt<-stab$coefficient[stab$feature==f]
                   if(!length(v)||pt==0) NA_real_ else 100*mean(sign(v)!=sign(pt))}))
cf <- merge(stab[coefficient!=0], ci, by="feature")[order(abs(coefficient))]
cf[, `:=`(lab = factor(lab, levels=lab), lo = coefficient - se, hi = coefficient + se)]
fwrite(cf, file.path(TABLES,"lasso_coef_bootstrap_ci.csv"))
cat(sprintf("max %% sign flip: %.2f | median SE %.2f vs median 95%% CI width %.2f\n",
    max(cf$pct_flip,na.rm=TRUE), median(cf$se), median(cf$ci_hi-cf$ci_lo)))

pB <- ggplot(cf, aes(lab, coefficient, fill = coefficient > 0)) +
  geom_hline(yintercept=0, colour="#666666", linewidth=0.3) +
  geom_col(colour="#1a1a1a", linewidth=0.25, width=0.7) +
  geom_errorbar(aes(ymin=lo, ymax=hi), width=0.25, linewidth=0.35, colour="#1a1a1a") +
  scale_fill_manual(values=c(`TRUE`=PWAcol,`FALSE`=HCcol),
                    labels=c(`TRUE`="Higher in PWA",`FALSE`="Higher in HC"), name=NULL) +
  coord_flip() +
  labs(title="B.", x=NULL, y="LASSO coefficient (log-odds)") +
  theme_marte() + theme(legend.position="bottom")

cm <- pred[, .N, by=.(true,pred_class)]
cm[, `:=`(True=ifelse(true==1,"PWA","HC"), Predicted=ifelse(pred_class==1,"PWA","HC"))]
cm[, Correct := ifelse(True == Predicted, "Correctly classified", "Misclassified")]
pC <- ggplot(cm, aes(Predicted, True, fill=Correct)) +
  geom_tile(colour="white", linewidth=1.2) +
  geom_text(aes(label=N, colour=Correct), size=4.6, fontface="bold", show.legend=FALSE) +
  scale_fill_manual(values=c(`Correctly classified`=STABLE, `Misclassified`="#E0E0E0"), name=NULL) +
  scale_colour_manual(values=c(`Correctly classified`="white", `Misclassified`="#1a1a1a")) +
  labs(title="C.", x="Predicted class", y="True class") +
  theme_marte() + theme(legend.position="bottom")

pD <- ggplot(stab[order(-selection_pct)],
             aes(reorder(lab, selection_pct), selection_pct, fill=selection_pct>=80)) +
  geom_col(colour="#1a1a1a", linewidth=0.25, width=0.7) +
  geom_hline(yintercept=80, linetype=2, colour="#666666", linewidth=0.4) +
  scale_fill_manual(values=c(`TRUE`=STABLE,`FALSE`="#BBBBBB"), guide="none") +
  scale_y_continuous(limits=c(0,100), expand=expansion(mult=c(0,.02))) +
  coord_flip() + labs(title="D.", x=NULL, y="Folds selecting the feature (%)") + theme_marte()

save_fig((pA | pB) / (pC | pD), "figure02", width = 11, height = 8.5)
