HERE <- local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) return(dirname(normalizePath(f)))
  normalizePath(".")
})
source(file.path(HERE, "..", "config.R"))
source(file.path(HERE, "_style.R"))
suppressPackageStartupMessages({ library(ggplot2); library(data.table) })
marte_defaults()

box <- function(id, x, y, label, fill, w = 0.85, h = 0.40)
  data.table(id = id, x = x, y = y, label = label, fill = fill, w = w, h = h)

STIM <- "#EBEBEB"; RUN <- "#DCE3EF"; INVC <- MC_COL; PART <- "#F5D9D4"; FEAT <- "#E8E8E8"

B <- rbindlist(list(
  box("stim", 1.0, 3.0, "Movie clip\nvideo, audio, subtitles",                     STIM),
  box("runs", 3.0, 3.0, "5 independent VLM runs\nGemini 2.5 Pro",                  RUN),
  box("clus", 5.0, 3.0, "Cluster labels across runs\nequivalence at cosine 0.63",  RUN),
  box("supp", 7.0, 3.0, "Keep clusters proposed by\n3 or more of the 5 runs",      RUN),
  box("floor",9.0, 3.0, "Drop concepts produced by\nfewer than 20% of controls",   RUN),
  box("inv",  11.0,3.0, "Main concept inventory\n39 concepts, 8 clips",            INVC),

  box("narr", 1.0, 1.0, "Participant narration\n105 speakers, 688 narrations",     PART),
  box("utt",  3.0, 1.0, "Segment into utterances\nStanza subject-verb units",      PART),
  box("emb",  5.0, 1.0, "Embed each utterance\nall-mpnet-base-v2",                 PART),
  box("score",8.0, 1.0, "Score against the inventory\nnearest concept at cosine 0.50",  PART, w = 1.15),
  box("feat", 11.0,1.0, "Completeness\nDistance to centroid\nSemantic coherence",  FEAT)
))

seg <- function(a, b, lane) {
  p <- B[id == a]; q <- B[id == b]
  data.table(x = p$x + p$w, xend = q$x - q$w, y = p$y, yend = q$y, lane = lane)
}
A <- rbindlist(list(
  seg("stim","runs","build"), seg("runs","clus","build"), seg("clus","supp","build"),
  seg("supp","floor","build"), seg("floor","inv","build"),
  seg("narr","utt","score"),  seg("utt","emb","score"),   seg("emb","score","score"),
  seg("score","feat","score")
))

X <- data.table(
  x    = c(B[id=="emb"]$x,            B[id=="inv"]$x),
  xend = c(B[id=="floor"]$x,          B[id=="score"]$x),
  y    = c(B[id=="emb"]$y + 0.40,     B[id=="inv"]$y - 0.40),
  yend = c(B[id=="floor"]$y - 0.40,   B[id=="score"]$y + 0.40))

p <- ggplot() +
  geom_rect(data = B, aes(xmin = x-w, xmax = x+w, ymin = y-h, ymax = y+h, fill = fill),
            colour = INK, linewidth = 0.35) +
  scale_fill_identity() +
  geom_text(data = B, aes(x = x, y = y, label = label),
            size = 2.8, family = "Helvetica", colour = "#222222", lineheight = 1.05) +
  geom_segment(data = A, aes(x = x, xend = xend, y = y, yend = yend),
               arrow = arrow(length = unit(0.10, "cm"), type = "closed"),
               linewidth = 0.35, colour = INK) +
  geom_segment(data = X, aes(x = x, xend = xend, y = y, yend = yend),
               arrow = arrow(length = unit(0.10, "cm"), type = "closed"),
               linewidth = 0.35, colour = "#777777", linetype = "22") +
  annotate("text", x = 5.45, y = 2.30, label = "control narrations",
           hjust = 0, size = 2.5, family = "Helvetica", colour = "#777777") +
  annotate("text", x = 10.05, y = 2.30, label = "inventory",
           hjust = 0, size = 2.5, family = "Helvetica", colour = "#777777") +
  annotate("text", x = 0.02, y = 3.62, label = "Inventory construction",
           hjust = 0, fontface = "bold", size = 3.3, family = "Helvetica", colour = "#222222") +
  annotate("text", x = 0.02, y = 1.62, label = "Narration scoring",
           hjust = 0, fontface = "bold", size = 3.3, family = "Helvetica", colour = "#222222") +
  coord_cartesian(xlim = c(-0.1, 12.2), ylim = c(0.3, 3.85), expand = FALSE) +
  theme_void(base_family = "Helvetica") +
  theme(plot.margin = margin(6, 6, 6, 6))

save_fig(p, "figureS1", width = 11.5, height = 3.4)
