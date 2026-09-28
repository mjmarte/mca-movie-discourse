HERE <- local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) return(dirname(normalizePath(f)))
  normalizePath(".")
})

for (fig in c("figure01.R", "figure02.R", "figure03.R")) {
  cat("\n==", fig, "==\n")

  ok <- tryCatch({ sys.source(file.path(HERE, fig), envir = new.env(parent = globalenv())); TRUE },
                 error = function(e) { cat("  failed:", conditionMessage(e), "\n"); FALSE })
  if (!ok) cat("  (continuing; see the error above for the missing input)\n")
}
