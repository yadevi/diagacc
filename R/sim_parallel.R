par_comb <- function(x) {
  list(
    LC   = lapply(x, function(x) x$LC),
    LCRE = lapply(x, function(x) x$LCRE),
    FM   = lapply(x, function(x) x$FM)
  )
}

#' Title
#'
#' @inheritParams run_sim
#' @param no.cores
#'
#' @export
run_sim_par <- function(object = NULL, B = 4, n = 250, tau = 0.08,
                        miss.prop = 0.2, data.gen = c("lc", "lcre", "fm"),
                        no.cores = parallel::detectCores(),
                        lc.method = c("MCMC", "EM"),
                        lcre.method = c("MCMC", "EM")) {
  # Initialise -----------------------------------------------------------------
  lc.method <- match.arg(lc.method, c("MCMC", "EM"))
  lcre.method <- match.arg(lcre.method, c("MCMC", "EM"))
  if (!is.null(object)) {  # Add additional simulations
    n <- extract_n(object)
    tau <- extract_tau(object)
    miss.prop <- extract_miss.prop(object)
    data.gen <- extract_data.gen(object)
    lc.method <- extract_lc.method(object)
    lcre.method <- extract_lcre.method(object)
  }
  data.gen <- match.arg(data.gen, c("lc", "lcre", "fm"))
  if (data.gen == "lc") gen_data <- gen_lc
  if (data.gen == "lcre") gen_data <- gen_lcre
  if (data.gen == "fm") gen_data <- gen_fm

  res.lc <- res.lcre <- res.fm <- list()

  sim.msg <- paste0("n = ", n, ", prev. = ", tau, ", missing gold = ",
                    miss.prop * 100, "%, data gen. mech. = ", toupper(data.gen),
                    "\n")
  cat(sim.msg)

  pb <- txtProgressBar(min = 0, max = B, style = 3)
  progress <- function(i) setTxtProgressBar(pb, i)
  cl <- parallel::makeCluster(no.cores)
  doSNOW::registerDoSNOW(cl)

  res <- foreach::`%dopar%`(
    foreach::foreach(
      i = seq_len(B),
      .packages = c("rjags", "runjags", "randomLCA", "coda"),
      .options.snow = list(progress = progress)
    ), {
      done <- FALSE
      while (!isTRUE(done)) {
        X <- gen_data(n = n, tau = tau, miss.prop = miss.prop)

        res.lc <- try(fit_lc(X, method = lc.method, gold.std = TRUE))
        res.lcre <- try(fit_lcre(X, quad.points = 189, method = lcre.method,
                                 gold.std = TRUE),
                        silent = TRUE)

        if (is.try_error(res.lc) | is.try_error(res.lcre)) {
          done <- FALSE
        } else {
          suppressWarnings(res.fm <- fit_fm(X, n.sample = 2000, silent = TRUE,
                                            gold.std = TRUE))
          done <- TRUE
        }
      }
      list("LC" = res.lc, "LCRE" = res.lcre, "FM" = res.fm)
    }
  )
  close(pb)
  parallel::stopCluster(cl)
  res <- par_comb(res)

  if (!is.null(object)) {
    res$LC <- c(object$LC, res$LC)
    res$LCRE <- c(object$LCRE, res$LCRE)
    res$FM <- c(object$FM, res$FM)
    B <- extract_B(object) + B
  }

  sim.settings <- list(B = B, n = n, tau = tau, miss.prop = miss.prop,
                       data.gen = data.gen, sim.msg = sim.msg,
                       lc.method = lc.method, lcre.method = lcre.method)

  res$sim.settings <- sim.settings
  class(res) <- "diagaccSim1"
  res
}

