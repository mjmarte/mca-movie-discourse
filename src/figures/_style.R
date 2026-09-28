suppressPackageStartupMessages(library(ggplot2))

HC_COL   <- "#3C5488"
PWA_COL  <- "#E64B35"
MC_COL   <- "#00A087"
INK      <- "#1a1a1a"
CONCEPT  <- "#9E9E9E"
CENTROID <- "#4D4D4D"

theme_marte <- function() {
  theme_minimal(base_size = 11, base_family = "Helvetica") +
    theme(
      axis.ticks       = element_blank(),
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(color = "#EBEBEB", linewidth = 0.25),
      strip.text       = element_text(face = "bold", size = 10),
      legend.position  = "bottom",
      legend.title     = element_text(size = 8.5),
      legend.text      = element_text(size = 8.5),
      axis.title       = element_text(size = 10, colour = "#222222"),
      axis.text        = element_text(size = 9, colour = "#666666"),
      plot.title       = element_text(face = "bold", size = 12, colour = "#222222",
                                      hjust = 0, margin = margin(b = 6)),
      plot.subtitle    = element_text(size = 9, color = "#666666", hjust = 0),
      plot.title.position = "panel"
    )
}

marte_defaults <- function() {
  theme_set(theme_marte())
  update_geom_defaults("point",
    list(shape = 21, colour = INK, stroke = 0.3, size = 2.5, fill = "gray35"))
  invisible(TRUE)
}

save_fig <- function(plot, name, width, height, dir = FIGURES) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  ggsave(file.path(dir, paste0(name, ".png")), plot,
         width = width, height = height, dpi = 300, bg = "white")
  ggsave(file.path(dir, paste0(name, ".pdf")), plot,
         width = width, height = height, bg = "white")
  cat(sprintf("wrote %s.png and %s.pdf (%.1f x %.1f in)\n", name, name, width, height))
}
