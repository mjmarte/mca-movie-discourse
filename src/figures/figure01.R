suppressPackageStartupMessages({
  library(data.table); library(tidyverse); library(patchwork); library(gghalves)
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
select <- dplyr::select; filter <- dplyr::filter
O <- TABLES; MD <- TABLES; FIG <- FIGURES
set.seed(SEED)
HCcol <- HC_COL; PWAcol <- PWA_COL; MCcol <- MC_COL
CONC <- CONCEPT; CENT <- CENTROID
SHORT <- CLIP_SHORT

pan<-fread(file.path(O,"panel_clusters_all.csv"))
pan[, clip:=factor(clip, levels=rev(CLIPS), labels=SHORT[rev(CLIPS)])]
pan[, Stage2:=ifelse(retained,"Retained","Removed")]
pan[, Support:=factor(support_runs, levels=c(3,4,5), labels=c("3 of 5","4 of 5","5 of 5"))]
pA<-ggplot(pan, aes(pct_hc, clip)) +
  geom_vline(xintercept=20, linetype=3, colour="#777777", linewidth=0.45) +
  geom_point(aes(fill=Stage2, size=Support), shape=21, colour=INK, stroke=0.3, alpha=0.9,
             position=position_jitter(height=0.14, width=0, seed=42)) +
  scale_fill_manual(values=c(Retained=MCcol, Removed="#D9D9D9"), name=NULL) +
  scale_size_manual(values=c(`3 of 5`=1.7,`4 of 5`=2.7,`5 of 5`=3.7),
                    name="VLM runs proposing\nthe concept") +
  annotate("text", x=20.5, y=8.75, label="20% threshold", size=2.7,
           colour="#666666", hjust=0, vjust=0) +
  scale_x_continuous(limits=c(0,100), breaks=seq(0,100,25),
                     expand=expansion(mult=c(0.03,0.03))) +
  coord_cartesian(ylim=c(0.5,9.4), clip="off") +
  guides(fill=guide_legend(order=1, override.aes=list(size=3)), size=guide_legend(order=2)) +
  labs(title="A.", x="Healthy controls producing the concept (%)", y=NULL) +
  theme_marte() + theme(legend.position="right", legend.box="vertical")

md <- fread(file.path(MD, "projection_coords.csv"))[method == "Metric MDS"]
md[, `:=`(x = x - mean(x), y = y - mean(y)), by = clip]
md[, s := max(sqrt(x^2 + y^2)), by = clip][, `:=`(x = x / s, y = y / s)]
md[, clip := factor(clip, levels = SHORT[CLIPS])]

LV  <- c("Healthy control", "Person with aphasia", "HC mean embedding", "PWA mean embedding",
         "Inventory concept", "Inventory centroid")
ppl <- md[kind %in% c("HC", "PWA")]
ppl[, layer := factor(fifelse(kind == "HC", "Healthy control", "Person with aphasia"),
                      levels = LV)]
gc  <- ppl[, .(x = mean(x), y = mean(y)), by = .(clip, kind)]
gc [, layer := factor(fifelse(kind == "HC", "HC mean embedding", "PWA mean embedding"), levels = LV)]
con <- md[kind == "Concept" ][, layer := factor("Inventory concept",  levels = LV)]
inv <- md[kind == "Centroid"][, layer := factor("Inventory centroid", levels = LV)]

pB <- ggplot() +
  stat_ellipse(data = ppl, aes(x, y, colour = layer, fill = layer), type = "norm",
               level = 0.95, geom = "polygon", alpha = 0.10, linewidth = 0.40,
               show.legend = FALSE) +
  geom_point(data = ppl, aes(x, y, fill = layer), shape = 21, colour = INK,
             stroke = 0.15, size = 1.15, alpha = 0.75) +
  geom_point(data = con, aes(x, y, fill = layer), shape = 22, colour = INK,
             stroke = 0.28, size = 1.6) +
  geom_point(data = inv, aes(x, y, fill = layer), shape = 23, colour = "white",
             stroke = 0.75, size = 3.1) +
  geom_point(data = gc,  aes(x, y, fill = layer), shape = 21, colour = "white",
             stroke = 0.75, size = 3.4) +
  scale_fill_manual(values = c(`Healthy control` = HCcol, `Person with aphasia` = PWAcol,
                               `HC mean embedding` = HCcol, `PWA mean embedding` = PWAcol,
                               `Inventory concept` = CONC, `Inventory centroid` = CENT),
                    breaks = LV, name = NULL, drop = FALSE) +
  scale_colour_manual(values = c(`Healthy control` = HCcol,
                                 `Person with aphasia` = PWAcol), guide = "none") +
  facet_wrap(~clip, nrow = 2) + coord_equal() +
  labs(title = "B.", x = "MDS dimension 1", y = "MDS dimension 2") +
  theme_marte() + theme(legend.position = "right", panel.grid.minor = element_blank(),
                        axis.text = element_blank()) +
  guides(fill = guide_legend(ncol = 1, override.aes = list(
    shape  = c(21, 21, 21, 21, 22, 23),
    size   = c(2.6, 2.6, 3.4, 3.4, 2.6, 3.1),
    colour = c(INK, INK, "white", "white", INK, "white"),
    stroke = c(0.3, 0.3, 0.75, 0.75, 0.28, 0.75), alpha = 1)))

EMB<-data_root()
ue<-fread(file.path(EMB,"utterance_embeddings.csv"))
ce<-fread(file.path(O,"concept_embeddings.csv"))
ana<-fread(file.path(data_root(),"features.csv"))
hc<-unique(ana[Group=="HC"]$Participant); pw<-unique(ana[Group=="PWA"]$Participant)
ec<-grep("^emb_",names(ue),value=TRUE); unit<-function(v) v/sqrt(sum(v^2))
dd<-rbindlist(lapply(CLIPS, function(cl){
  V<-as.matrix(ce[clip==cl, ..ec]); M<-unit(colMeans(V))
  S<-ue[clip==cl & participant_id %in% c(hc,pw)]
  U<-as.matrix(S[, ..ec]); U<-U/sqrt(rowSums(U^2))
  P<-data.table(pid=S$participant_id, du=as.numeric(1-U%*%M))[, .(d=mean(du)), by=pid]
  data.table(clip=cl, Group=ifelse(P$pid %in% hc,"HC","PWA"), d=P$d)}))
dd[, clip:=factor(clip, levels=CLIPS, labels=SHORT[CLIPS])]
dd[, xnum:=as.integer(clip)][, grp:=interaction(clip,Group,drop=TRUE)]
dd[, xpt:=xnum+ifelse(Group=="HC",-0.34,0.06)+runif(.N,-0.045,0.045)]
dd[, xbox:=xnum+ifelse(Group=="HC",-0.24,0.16)]
dd[, xvio:=xnum+ifelse(Group=="HC",-0.19,0.21)]
pC<-ggplot(dd, aes(xnum,d)) +
  gghalves::geom_half_violin(aes(x=xvio, group=grp, fill=Group), side="r", colour=INK,
                             linewidth=0.28, alpha=0.45, width=0.30) +
  geom_boxplot(aes(x=xbox, group=grp), width=0.085, outlier.shape=NA, alpha=0.9,
               fill="white", linewidth=0.28) +
  geom_point(aes(x=xpt, fill=Group), shape=21, colour=INK, stroke=0.2, size=1.25, alpha=0.8) +
  scale_fill_manual(values=c(HC=HCcol,PWA=PWAcol), name=NULL,
                    labels=c("Healthy control","Person with aphasia")) +
  scale_x_continuous(breaks=seq_along(levels(dd$clip)), labels=levels(dd$clip)) +
  labs(title="C.", x=NULL, y="Cosine distance to inventory centroid") +
  theme_marte() + theme(legend.position="right",
                        axis.text.x=element_text(angle=18, hjust=1))

f<-pA / pB / pC + plot_layout(heights=c(0.9,1.35,1.05))
save_fig(f, "figure01", width = 10.5, height = 12.6)
