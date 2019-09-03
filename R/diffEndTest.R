#' @include utils.R


.diffEndTest <- function(models, global = TRUE, pairwise = FALSE){
  # TODO: add fold changes
  # TODO: check if this is different to comparing knot coefficients
  # TODO: adjust null distribution with weights

  if(is(models, "list")){
    sce <- FALSE
  } else if(is(models, "SingleCellExperiment")){
    sce <- TRUE
  }

  # get predictor matrix for every lineage.
  if(!sce){ # list output of fitGAM
    modelTemp <- .getModelReference(models)
    nCurves <- length(modelTemp$smooth)
    if (nCurves == 1) stop("You cannot run this test with only one lineage.")
    if(nCurves == 2 & pairwise == TRUE){
      message("Only two lineages; skipping pairwise comparison.")
      pairwise <- FALSE
    }

    data <- modelTemp$model

    for (jj in seq_len(nCurves)) {
      df <- .getPredictEndPointDf(modelTemp$model, jj)
      assign(paste0("X",jj),
             predict(modelTemp, newdata = df, type = "lpmatrix"))
    }
  } else if(sce){

    dm <- colData(models)$tradeSeq$dm # design matrix
    nCurves <- length(grep(x = colnames(dm), pattern = "t[1-9]"))
    if (nCurves == 1) stop("You cannot run this test with only one lineage.")
    if(nCurves == 2 & pairwise == TRUE){
      message("Only two lineages; skipping pairwise comparison.")
      pairwise <- FALSE
    }

    # get lp matrix
    slingshotColData <- colData(models)$slingshot
    for (jj in seq_len(nCurves)) {
      df <- .getPredictEndPointDf(dm, jj)
      assign(paste0("X",jj),
             predictGAM(lpmatrix = colData(models)$tradeSeq$X,
                        df = df,
                        pseudotime = slingshotColData[,grep(x = colnames(slingshotColData),
                                                            pattern = "pseudotime")]))
    }
  }


  # construct pairwise contrast matrix
  if(!sce){
    p <- length(coef(modelTemp))
  } else if(sce){
    p <- ncol(colData(models)$tradeSeq$X)
  }

  combs <- combn(nCurves,m = 2)
  L <- matrix(0, nrow = p, ncol = ncol(combs))
  colnames(L) <- apply(combs, 2, paste, collapse = "_")
  for (jj in seq_len(ncol(combs))) {
    curvesNow <- combs[,jj]
    L[,jj] <- get(paste0("X", curvesNow[1])) - get(paste0("X",curvesNow[2]))
  }
  if(!sce) rm(modelTemp)

  # perform global statistical test for every model
  if (global) {
    if(!sce){ #gam list output
      waldResultsOmnibus <- lapply(models, function(m){
        if (class(m)[1] == "try-error") return(c(NA, NA, NA))
        beta <- matrix(coef(m), ncol = 1)
        Sigma <- m$Vp
        waldTest(beta, Sigma, L)
      })

    } else if(sce){ #singleCellExperiment output
      waldResultsOmnibus <- lapply(1:nrow(models), function(ii){
        beta <- t(rowData(models)$tradeSeq$beta[[1]][ii,])
        Sigma <- rowData(models)$tradeSeq$Sigma[[ii]]
        waldTest(beta, Sigma, L)
      })
      names(waldResultsOmnibus) <- rownames(models)
    }

    #process output.
    waldResults <- do.call(rbind,waldResultsOmnibus)
    colnames(waldResults) <- c("waldStat", "df", "pvalue")
    waldResults <- as.data.frame(waldResults)
  }

  # perform pairwise comparisons
  if (pairwise) {
    if(!sce){ # gam list output
      waldResultsPairwise <- lapply(models, function(m){
        if (class(m)[1] == "try-error") {
          return(matrix(NA, nrow = ncol(L), ncol = 3))
        }
        beta <- matrix(coef(m), ncol = 1)
        Sigma <- m$Vp
        t(sapply(seq_len(ncol(L)), function(ii){
          waldTest(beta, Sigma, L[, ii, drop = FALSE])
        }))
      })
    } else if(sce){
      waldResultsPairwise <- lapply(1:nrow(models), function(ii){
        beta <- t(rowData(models)$tradeSeq$beta[[1]][ii,])
        Sigma <- rowData(models)$tradeSeq$Sigma[[ii]]
        t(sapply(seq_len(ncol(L)), function(ii){
          waldTest(beta, Sigma, L[, ii, drop = FALSE])
        }))
      })
      names(waldResultsPairwise) <- rownames(models)
    }

    # clean pairwise results
    contrastNames <- unlist(lapply(strsplit(colnames(L), split = "_"),
                                   paste, collapse = "vs"))

    colNames <- c(paste0("waldStat_",contrastNames),
                  paste0("df_",contrastNames),
                  paste0("pvalue_",contrastNames))
    orderByContrast <- unlist(c(mapply(seq, seq_along(colNames),
                                       length(waldResultsPairwise[[1]]),
                                       by = 3)))
    waldResAllPair <- do.call(rbind,
                              lapply(waldResultsPairwise,function(x){
                                matrix(x, nrow = 1, dimnames = list(NULL, colNames))[, orderByContrast]
                              }))
  }

  # return output
  if (global == TRUE & pairwise == FALSE) return(waldResults)
  if (global == FALSE & pairwise == TRUE) return(waldResAllPair)
  if (global == TRUE & pairwise == TRUE) {
    waldAll <- cbind(waldResults, waldResAllPair)
    return(waldAll)
  }
}


#' Perform statistical test to check for DE between final stages of every
#'  lineage.
#' @param models Typically the output from
#' \code{\link{fitGAM}}, either a list of fitted GAM models, or an object of
#' \code{SingleCellExperiment} class.
#' @param global If TRUE, test for all pairwise comparisons simultaneously.
#' @param pairwise If TRUE, test for all pairwise comparisons independently.
#' @importFrom magrittr %>%
#' @examples
#' data(gamList, package = "tradeSeq")
#' diffEndTest(gamList, global = TRUE, pairwise = TRUE)
#' @return A matrix with the wald statistic, the number of df and the p-value
#'  associated with each gene for all the tests performed. If the testing
#'  procedure was unsuccessful, the procedure will return NA test statistics and
#'  p-values.
#' @export
#' @name diffEndTest
#' @import SingleCellExperiment
setMethod(f = "diffEndTest",
          signature = c(models = "SingleCellExperiment"),
          definition = function(models,
                                global = TRUE,
                                pairwise = FALSE){

            res <- .diffEndTest(models = models,
                                global = global,
                                pairwise = pairwise)
            return(res)

          }
)

#' @rdname diffEndTest
#' @export
setMethod(f = "diffEndTest",
          signature = c(models = "list"),
          definition = function(models,
                                global = TRUE,
                                pairwise = FALSE){

            res <- .diffEndTest(models = models,
                                global = global,
                                pairwise = pairwise)
            return(res)

          }
)