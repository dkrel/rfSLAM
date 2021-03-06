partial.rfsrc <- function(
  object,
  m.target = NULL,
  partial.type = NULL,
  partial.xvar = NULL,
  partial.values = NULL,
  partial.xvar2 = NULL,
  partial.values2 = NULL,
  partial.time = NULL,
  oob = TRUE,
  seed = NULL,
  do.trace = FALSE,
  ...)
{
  ## Hidden options.
  user.option <- list(...)
  terminal.qualts <- is.hidden.terminal.qualts(user.option)
  terminal.quants <- is.hidden.terminal.quants(user.option)
  ## Object consistency.  Note that version checking is NOT
  ## implemented in this mode. (TBD)
  if (missing(object)) {
    stop("object is missing!")
  }
  if (sum(inherits(object, c("rfsrc", "grow"), TRUE) == c(1, 2)) != 2    &
      sum(inherits(object, c("rfsrc", "forest"), TRUE) == c(1, 2)) != 2) {
    stop("this function only works for objects of class `(rfsrc, grow)' or '(rfsrc, forest)'")
  }
  ## Acquire the forest.
  if (sum(inherits(object, c("rfsrc", "grow"), TRUE) == c(1, 2)) == 2) {
    if (is.null(object$forest)) {
      stop("The forest is empty.  Re-run rfsrc (grow) call with forest=TRUE")
    }
    object <- object$forest
  }
    else {
      ## Object is already a forest.
    }
  ## Multivariate family details.
  family <- object$family
  splitrule <- object$splitrule
  ## Pull the x-variable and y-outcome names from the grow object.
  xvar.names <- object$xvar.names
  yvar.names <- object$yvar.names
  ## Verify the x-var.
  if (length(which(xvar.names == partial.xvar)) != 1) {
    stop("x-variable specified incorrectly:  ", partial.xvar)
  }
  ## Verify the x-var2.
  if (!is.null(partial.xvar2)) {   
      if (length(partial.xvar2) != length(partial.values2)) {
          stop("second order x-variable and value vectors not of same length:  ", length(partial.xvar2), "vs", length(partial.values2))
      }
      for (i in 1:length(partial.xvar2)) {
          if (length(which(xvar.names == partial.xvar2[i])) != 1) {
              stop("second order x-variable element", i, "specified incorrectly:  ", partial.xvar2[i])
          }
      }
  }
  ## Caution:  There are no checks on partial.type.  Note that "rel.freq" and "mort"
  ## are equivalent from a native code perspective.
  ## Determine the immutable yvar factor map which is needed for
  ## classification sexp dimensioning.  But, first convert object$yvar
  ## to a data frame which is required for factor processing.
  object$yvar <- as.data.frame(object$yvar)
  colnames(object$yvar) <- yvar.names
  yfactor <- extract.factor(object$yvar)
  m.target.idx <- get.outcome.target(family, yvar.names, m.target)
  ## Get the y-outcome type and number of levels
  yvar.types <- get.yvar.type(family, yfactor$generic.types, yvar.names, object$coerce.factor)
  yvar.nlevels <- get.yvar.nlevels(family, yfactor$nlevels, yvar.names, object$yvar, object$coerce.factor)
  ## Get event information for survival families.
  event.info <- get.event.info(object)
  ## CR.bits assignment.
  cr.bits <- get.cr.bits(family)
  ## Determine the immutable xvar factor map.
  xfactor <- extract.factor(object$xvar)
  ## Get the x-variable type and number of levels.
  xvar.types <- get.xvar.type(xfactor$generic.types, xvar.names, object$coerce.factor)
  xvar.nlevels <- get.xvar.nlevels(xfactor$nlevels, xvar.names, object$xvar, object$coerce.factor)
  ## Initialize the number of trees in the forest.
  ntree <- object$ntree
  ## Use the training data na.action protocol.
  na.action = object$na.action
  ## Data conversion for training data.
  xvar <- as.matrix(data.matrix(object$xvar))
  yvar <- as.matrix(data.matrix(object$yvar))
  ## Set the y dimension.
  r.dim <- ncol(cbind(yvar))
  ## Remove row and column names for proper processing by the native
  ## code.  Set the dimensions.
  rownames(xvar) <- colnames(xvar) <- NULL
  n.xvar <- ncol(xvar)
  n <- nrow(xvar)
  ## There is no test data.
  outcome = "train"
  ## Initialize the low bits.
  oob.bits <- get.oob(oob)
  bootstrap.bits <- get.bootstrap(object$bootstrap)
  na.action.bits <- get.na.action(na.action)
  ## Initalize the high bits
  samptype.bits <- get.samptype(object$samptype)
  partial.bits <- get.partial(length(partial.values))
  terminal.qualts.bits <- get.terminal.qualts(terminal.qualts, object$terminal.qualts)
  terminal.quants.bits <- get.terminal.quants(terminal.quants, object$terminal.quants)
  seed <- get.seed(seed)
  do.trace <- get.trace(do.trace)
  ## Check that htry is initialized.  If not, set it zero.
  ## This is necessary for backwards compatibility with 2.3.0
    if (is.null(object$htry)) {
        htry <- 0
    }
    else {
        htry <- object$htry
    }
    ## Marker for start of native forest topology.  This can change with the outputs requested.
    ## For the arithmetic related to the pivot point, you need to refer to stackOutput.c and in
    ## particular, stackForestOutputObjects().
    pivot <- which(names(object$nativeArray) == "treeID")
  nativeOutput <- tryCatch({.Call("rfsrcPredict",
                                  as.integer(do.trace),
                                  as.integer(seed),
                                  as.integer(
                                      oob.bits +
                                      bootstrap.bits +
                                      cr.bits), 
                                  as.integer(
                                    samptype.bits +
                                      na.action.bits +
                                        terminal.qualts.bits +
                                          terminal.quants.bits +
                                            partial.bits),
                                  ## >>>> start of maxi forest object >>>>
                                  as.integer(ntree),
                                  as.integer(n),
                                  as.integer(r.dim),
                                  as.character(yvar.types),
                                  as.integer(yvar.nlevels),
                                  as.double(as.vector(yvar)),
                                  as.integer(ncol(xvar)),
                                  as.character(xvar.types),
                                  as.integer(xvar.nlevels),
                                  as.double(xvar),
                                  as.integer(object$sampsize),
                                  as.integer(object$samp),
                                  as.double(object$case.wt),
                                  as.integer(length(event.info$time.interest)),
                                  as.double(event.info$time.interest),
                                  as.integer(object$totalNodeCount),
                                  as.integer(object$seed),
                                  as.integer(htry),
                                  as.integer((object$nativeArray)$treeID),
                                  as.integer((object$nativeArray)$nodeID),
                                  list(as.integer((object$nativeArray)$parmID),
                                  as.double((object$nativeArray)$contPT),
                                  as.integer((object$nativeArray)$mwcpSZ),
                                  as.integer((object$nativeFactorArray)$mwcpPT)),
                                  if (htry > 0) {
                                      list(as.integer((object$nativeArray)$hcDim),
                                      as.double((object$nativeArray)$contPTR))
                                  } else { NULL },
                                  if (htry > 1) {
                                      lapply(0:htry-2, function(x) {as.integer(object$nativeArray[[pivot + 9 + (0 * htry) + x]])})
                                  } else { NULL },
                                  if (htry > 1) {
                                      lapply(0:htry-2, function(x) {as.double(object$nativeArray[[pivot + 9 + (1 * htry) + x]])})
                                  } else { NULL },
                                  if (htry > 1) {
                                      lapply(0:htry-2, function(x) {as.double(object$nativeArray[[pivot + 9 + (2 * htry) + x]])})
                                  } else { NULL },
                                  if (htry > 1) {
                                      lapply(0:htry-2, function(x) {as.integer(object$nativeArray[[pivot + 9 + (3 * htry) + x]])})
                                  } else { NULL },
                                  if (htry > 1) {
                                      lapply(0:htry-2, function(x) {as.integer(object$nativeArray[[pivot + 9 + (4 * htry) + x]])})
                                  } else { NULL },
                                  as.integer(object$nativeArrayTNDS$tnRMBR),
                                  as.integer(object$nativeArrayTNDS$tnAMBR),
                                  as.integer(object$nativeArrayTNDS$tnRCNT),
                                  as.integer(object$nativeArrayTNDS$tnACNT),
                                  as.double((object$nativeArrayTNDS$tnSURV)),
                                  as.double((object$nativeArrayTNDS$tnMORT)),
                                  as.double((object$nativeArrayTNDS$tnNLSN)),
                                  as.double((object$nativeArrayTNDS$tnCSHZ)),
                                  as.double((object$nativeArrayTNDS$tnCIFN)),
                                  as.double((object$nativeArrayTNDS$tnREGR)),
                                  as.integer((object$nativeArrayTNDS$tnCLAS)),
                                  ## <<<< end of maxi forest object <<<<
                                  as.integer(m.target.idx),
                                  as.integer(length(m.target.idx)),
                                  as.integer(0),  ## Pruning disabled
                                    
                                  as.integer(0),     ## Importance disabled
                                  as.integer(NULL),  ## Importance disabled
                                  ## Partial variables enabled.  Note the as.integer is needed.
                                  list(as.integer(get.type(family, partial.type)),
                                       as.integer(which(xvar.names == partial.xvar)),
                                       as.integer(length(partial.values)),
                                       as.double(partial.values),
                                       as.integer(length(partial.xvar2)),
                                       if (length(partial.xvar2) == 0) NULL else as.integer(match(partial.xvar2, xvar.names)),
                                       as.double(partial.values2)),
                                  as.integer(0),     ## Subsetting disabled.
                                  as.integer(NULL),  ## Subsetting disabled.
                                  as.integer(0),    ## New data disabled.
                                  as.integer(0),    ## New data disabled.
                                  as.double(NULL),  ## New data disabled.
                                  as.double(NULL),  ## New data disabled.
                                  as.integer(ntree), ## err.block is hard-coded.
                                  as.integer(get.rf.cores()))}, error = function(e) {
                                    print(e)
                                    NULL})
  ## check for error return condition in the native code
  if (is.null(nativeOutput)) {
    stop("An error has occurred in prediction.  Please turn trace on for further analysis.")
  }
  rfsrcOutput <- list(call = match.call(),
                      family = family,
                      partial.time = partial.time)
  ## Subset the user time vector from the grow time interest vector.
  if (grepl("surv", family)) {
      ## Get the indices of the closest points of the grow time interest vector.
      ## Exact:
      ## partial.time.idx <- match(partial.time, event.info$time.interest)
      ## Closest:
      partial.time.idx <- sapply(partial.time, function(x) {max(which(event.info$time.interest <= x))})
      if (sum(is.na(partial.time.idx)) > 0) {
          stop("partial.time must be a subset of the time interest vector contained in the model")
      }
  }
  if (family == "surv") {
    if ((partial.type == "rel.freq") || (partial.type == "mort")) {
      mort.names <- list(NULL, NULL)
      ## Incoming from the native code:
      ##   type = mort
      ##   -> of dim [length(partial.values)] x [1] x [1] x [n]
      ## Outgoing to the R code:
      ##   -> of dim [n] x [length(partial.values)]  
      survOutput <- (if (!is.null(nativeOutput$partialSurv))
                       array(nativeOutput$partialSurv,
                             c(n, length(partial.values)),
                             dimnames=mort.names) else NULL)
    }
    else if (partial.type == "chf") {
      nlsn.names <- list(NULL, NULL, NULL)
      ## Incoming from the native code:
      ##   type = chf
      ##   -> of dim [length(partial.values)] x [1] x [length(partial.time)] x [n]
      ## Outgoing to the R code:
      ##   -> of dim [n] x [length(partial.time)] x [length(partial.values)]  
      survOutput <- (if (!is.null(nativeOutput$partialSurv))
                       array(nativeOutput$partialSurv,
                             c(n, length(event.info$time.interest), length(partial.values)),
                             dimnames=nlsn.names) else NULL)
      if (!is.null(survOutput)) {
        survOutput <- survOutput[, partial.time.idx, , drop=FALSE]
      }
    }
      else if (partial.type == "surv") {
        surv.names <- list(NULL, NULL, NULL)
        ## Incoming from the native code:
        ##   type = surv
        ##   -> of dim [length(partial.values)] x [1] x [length(partial.time)] x [n]
        ## Outgoing to the R code:
        ##   -> of dim [n] x [length(partial.time)] x [length(partial.values)]  
        survOutput <- (if (!is.null(nativeOutput$partialSurv))
                         array(nativeOutput$partialSurv,
                               c(n, length(event.info$time.interest), length(partial.values)),
                               dimnames=surv.names) else NULL)
        if (!is.null(survOutput)) {
          survOutput <- survOutput[, partial.time.idx, , drop=FALSE]
        }
      }
        else {
          stop("Invalid choice for 'partial.type' option:  ", partial.type)
        }
    rfsrcOutput <- c(rfsrcOutput, survOutput = list(survOutput))
  }
  else if (family == "surv-CR") {
    if (partial.type == "years.lost") {
      yrls.names <- list(NULL, NULL, NULL)
      ## Incoming from the native code:
      ##   type = years.lost
      ##   -> of dim [length(partial.values)] x [length(event.info$event.type)] x [1] x [n]
      ## Outgoing to the R code:
      ##   -> of dim [n] x [length(event.info$event.type)] x [length(partial.values)]  
      survOutput <- (if (!is.null(nativeOutput$partialSurv))
                       array(nativeOutput$partialSurv,
                             c(n, length(event.info$event.type), length(partial.values)),
                             dimnames=yrls.names) else NULL)
    }
      else if (partial.type == "cif") {
        cifn.names <- list(NULL, NULL, NULL, NULL)
        ## Incoming from the native code:
        ##   type = cif
        ##   -> of dim [length(partial.values)] x [length(event.info$event.type)] x [length(partial.time)] x [n]
        ## Outgoing to the R code:
        ##   -> of dim [n] x [length(partial.time)] x [length(event.info$event.type)] x [length(partial.values)]
        survOutput <- (if (!is.null(nativeOutput$partialSurv))
                         array(nativeOutput$partialSurv,
                               c(n, length(event.info$time.interest), length(event.info$event.type), length(partial.values)),
                               dimnames=cifn.names) else NULL)
        if (!is.null(survOutput)) {
          survOutput <- survOutput[, partial.time.idx, , , drop=FALSE]
        }
      }
        else if (partial.type == "chf") {
          chfn.names <- list(NULL, NULL, NULL, NULL)
          ## Incoming from the native code:
          ##   type = chfn
          ##   -> of dim [length(partial.values)] x [length(event.info$event.type)] x [length(partial.time)] x [n]
          ## Outgoing to the R code:
          ##   -> of dim [n] x [length(partial.time)] x [length(event.info$event.type)] x [length(partial.values)]
          survOutput <- (if (!is.null(nativeOutput$partialSurv))
                           array(nativeOutput$partialSurv,
                                 c(n, length(event.info$time.interest), length(event.info$event.type), length(partial.values)),
                                 dimnames=chfn.names) else NULL)
          if (!is.null(survOutput)) {
            survOutput <- survOutput[, partial.time.idx, , , drop=FALSE]
          }
        }
          else {
            stop("Invalid choice for 'partial.type' option:  ", partial.type)
          }
    rfsrcOutput <- c(rfsrcOutput, survOutput = list(survOutput))
  }
    else {
      ## We consider "R", "I", and "C" outcomes.  The outcomes are grouped
      ## by type and sequential.  That is, the first "C" encountered in the
      ## response type vector is in position [[1]] in the classification output
      ## list, the second "C" encountered is in position [[2]] in the
      ## classification output list, and so on.  The same applies to the
      ## regression outputs.  We also have a mapping from the outcome slot back
      ## to the original response vector type, given by the following:
      ## Given yvar.types = c("R", "C", "R", "C", "R" , "I")
      ## regr.index[1] -> 1
      ## regr.index[2] -> 3
      ## regr.index[3] -> 5
      ## clas.index[1] -> 2
      ## clas.index[2] -> 4
      ## clas.index[3] -> 6
      ## This will pick up all "C" and "I".
      class.index <- which(yvar.types != "R")
      class.count <- length(class.index)
      regr.index <- which(yvar.types == "R")
      regr.count <- length(regr.index)
      if (class.count > 0) {
        ## Create and name the classification outputs.
        classOutput <- vector("list", class.count)
        names(classOutput) <- yvar.names[class.index]
        ## Vector to hold the number of levels in each factor response. 
        levels.count <- array(0, class.count)
        ## List to hold the names of levels in each factor response. 
        levels.names <- vector("list", class.count)
        counter <- 0
        for (i in class.index) {
            counter <- counter + 1
            ## Note that [i] is the actual index of the y-variables and not a sequential iterator.
            ## The sequential iteratior is [counter]
            levels.count[counter] <- yvar.nlevels[i]
            if (yvar.types[i] == "C") {
              ## This an unordered factor.
              ## Here, we don't know the sequence of the unordered factor list, so we identify the factor by name.
              levels.names[[counter]] <- yfactor$levels[[which(yfactor$factor == yvar.names[i])]]
            }
              else {
                ## This in an ordered factor.
                ## Here, we don't know the sequence of the ordered factor list, so we identify the factor by name.
                levels.names[[counter]] <- yfactor$order.levels[[which(yfactor$order == yvar.names[i])]]
              }
        }
        iter.start <- 0
        iter.end   <- 0
        offset <- vector("list", class.count)
        for (p in 1:length(partial.values)) {
          for (k in 1:length(m.target.idx)) {
            target.idx <- which (class.index == m.target.idx[k])
            if (length(target.idx) > 0) {
              iter.start <- iter.end
              iter.end <- iter.start + ((1 + levels.count[target.idx]) * n)
              offset[[target.idx]] <- c(offset[[target.idx]], (iter.start+1):iter.end)
            }
          }
        }
        for (i in 1:length(m.target.idx)) {
          target.idx <- which (class.index == m.target.idx[i])
          if (length(target.idx) > 0) {
            ens.names <- list(NULL, c("all", levels.names[[target.idx]]), NULL)
            ## Incoming from the native code:
            ##   type = NULL
            ##   -> of dim [length(partial.values)] x [length(1 + yvar.nlevels[.]] x [n]
            ## Outgoing to the R code:
            ##   -> of dim [n] x [1 + yvar.nlevels[.]] x [length(partial.values)]
            ensemble <- (if (!is.null(nativeOutput$partialClas))
                             array(nativeOutput$partialClas[offset[[target.idx]]],
                                   c(n, 1 + levels.count[target.idx], length(partial.values)),
                                   dimnames=ens.names) else NULL)
            classOutput[[target.idx]] <- ensemble
            remove(ensemble)
          }
        }
        rfsrcOutput <- c(rfsrcOutput, classOutput = list(classOutput))        
      }
      if (regr.count > 0) {
        ## Create and name the classification outputs.
        regrOutput <- vector("list", regr.count)
        names(regrOutput) <- yvar.names[regr.index]
        iter.start <- 0
        iter.end   <- 0
        offset <- vector("list", regr.count)
        for (p in 1:length(partial.values)) {
          for (k in 1:length(m.target.idx)) {
            target.idx <- which (regr.index == m.target.idx[k])
            if (length(target.idx) > 0) {
              iter.start <- iter.end
              iter.end <- iter.start + n
              offset[[target.idx]] <- c(offset[[target.idx]], (iter.start+1):iter.end)
            }
          }
        }
        for (i in 1:length(m.target.idx)) {
          target.idx <- which (regr.index == m.target.idx[i])
          if (length(target.idx) > 0) {
            ens.names <- list(NULL, NULL)
            ## Incoming from the native code:
            ##   type = NULL
            ##   -> of dim [length(partial.values)] x [1] x [n]
            ## Outgoing to the R code:
            ##   -> of dim [n] x [length(partial.values)]
            ensemble <- (if (!is.null(nativeOutput$partialRegr))
                             array(nativeOutput$partialRegr[offset[[target.idx]]],
                                   c(n, length(partial.values)),
                                   dimnames=ens.names) else NULL)
            regrOutput[[target.idx]] <- ensemble
            remove(ensemble)
          }
        }
        rfsrcOutput <- c(rfsrcOutput, regrOutput = list(regrOutput))
      }
    }
  class(rfsrcOutput) <- c("rfsrc", "partial",   family)
  return (rfsrcOutput)
}


#' Acquire Partial Effect of a Variable
#' 
#' Acquire the partial effect of a variable on the ensembles.
#' 
#' 
#' A list of length equal to the number of outcomes (length is one for
#' univariate families) with entries depending on the underlying family:
#' 
#' \enumerate{ \item For regression, the predicted response is returned of dim
#' \code{[n] x [length(partial.values)]}.
#' 
#' \item For classification, the predicted probabilities are returned of dim
#' \code{[n] x [1 + yvar.nlevels[.]] x [length(partial.values)]}.
#' 
#' \item For survival, the choices are: \itemize{ \item Relative frequency of
#' mortality (\code{rel.freq}) or mortality (\code{mort}) is of dim \code{[n] x
#' [length(partial.values)]}.  \item The cumulative hazard function
#' (\code{chf}) is of dim \code{[n] x [length(partial.time)] x
#' [length(partial.values)]}.  \item The survival function (\code{surv}) is of
#' dim \code{[n] x [length(partial.time)] x [length(partial.values)]}.  }
#' 
#' \item For competing risks, the choices are: \itemize{ \item The expected
#' number of life years lost (\code{years.lost}) is of dim \code{[n] x
#' [length(event.info$event.type)] x [length(partial.values)]}.  \item The
#' cumulative incidence function (\code{cif}) is of dim \code{[n] x
#' [length(partial.time)] x [length(event.info$event.type)] x
#' [length(partial.values)]}.  \item The cumulative hazard function
#' (\code{chf}) is of dim \code{[n] x [length(partial.time)] x
#' [length(event.info$event.type)] x [length(partial.values)]}.  }
#' 
#' }
#' 
#' @aliases partial.rfsrc partial
#' @param object An object of class \code{(rfsrc, grow)}.
#' @param m.target Character value for multivariate families specifying the
#' target outcome to be used.  If left unspecified, the algorithm will choose a
#' default target.
#' @param partial.type Character value of the type of predicted value.  See
#' details below.
#' @param partial.xvar Character value specifying the single primary partial
#' x-variable to be used.
#' @param partial.values Vector of values that the primary partialy x-variable
#' will assume.
#' @param partial.xvar2 Vector of character values specifying the second order
#' x-variables to be used.
#' @param partial.values2 Vector of values that the second order x-variables
#' will assume.  Each second order x-variable can only assume a single value.
#' This the length of \code{partial.xvar2} and \code{partial.values2} will be
#' the same.  In addition, the user must do the appropriate conversion for
#' factors, and represent a value as a numeric element.
#' @param partial.time For survival families, the time at which the predicted
#' survival value is evaluated at (depends on \code{partial.type}).
#' @param oob OOB (TRUE) or in-bag (FALSE) predicted values.
#' @param seed Negative integer specifying seed for the random number
#' generator.
#' @param do.trace Number of seconds between updates to the user on approximate
#' time to completion.
#' @param ... Further arguments passed to or from other methods.
#' @author Hemant Ishwaran and Udaya B. Kogalur
#' @seealso \command{\link{plot.variable.rfsrc}}
#' @references Ishwaran H., Kogalur U.B. (2007).  Random survival forests for
#' R, \emph{Rnews}, 7(2):25-31.
#' 
#' Ishwaran H., Kogalur U.B., Blackstone E.H. and Lauer M.S.  (2008).  Random
#' survival forests, \emph{Ann. App.  Statist.}, 2:841-860.
#' 
#' Ishwaran H., Gerds T.A., Kogalur U.B., Moore R.D., Gange S.J. and Lau B.M.
#' (2014). Random survival forests for competing risks.  \emph{Biostatistics},
#' 15(4):757-773.
#' @keywords partial
#' @examples
#' 
#' \donttest{
#' ## ------------------------------------------------------------
#' ## survival/competing risk
#' ## ------------------------------------------------------------
#' 
#' ## survival
#' data(veteran, package = "randomForestSRC")
#' v.obj <- rfsrc(Surv(time,status)~., veteran, nsplit = 10, ntree = 100)
#' partial.obj <- partial(v.obj,
#'   partial.type = "rel.freq",
#'   partial.xvar = "age",
#'   partial.values = v.obj$xvar[, "age"],
#'   partial.time = v.obj$time.interest)
#' 
#' ## competing risks
#' data(follic, package = "randomForestSRC")
#' follic.obj <- rfsrc(Surv(time, status) ~ ., follic, nsplit = 3, ntree = 100)
#' partial.obj <- partial(follic.obj,
#'   partial.type = "cif",
#'   partial.xvar = "age",
#'   partial.values = follic.obj$xvar[, "age"],
#'   partial.time = follic.obj$time.interest,
#'   oob = TRUE)
#' 
#' ## regression
#' airq.obj <- rfsrc(Ozone ~ ., data = airquality)
#' partial.obj <- partial(airq.obj,
#'   partial.xvar = "Wind",
#'   partial.values = airq.obj$xvar[, "Wind"],
#'   oob = FALSE)
#' 
#' ## classification
#' iris.obj <- rfsrc(Species ~., data = iris)
#' partial.obj <- partial(iris.obj,
#'   partial.xvar = "Sepal.Length",
#'   partial.values = iris.obj$xvar[, "Sepal.Length"])
#' 
#' ## multivariate mixed outcomes
#' mtcars2 <- mtcars
#' mtcars2$carb <- factor(mtcars2$carb)
#' mtcars2$cyl <- factor(mtcars2$cyl)
#' mtcars.mix <- rfsrc(Multivar(carb, mpg, cyl) ~ ., data = mtcars2)
#' partial.obj <- partial(mtcars.mix,
#'   partial.xvar = "disp",
#'   partial.values = mtcars.mix$xvar[, "disp"])
#' 
#' ## second order variable specification
#' mtcars.obj <- rfsrc(mpg ~., data = mtcars)
#' partial.obj <- partial(mtcars.obj,
#'   partial.xvar = "cyl",
#'   partial.values = c(4, 8),
#'   partial.xvar2 = c("gear", "disp", "carb"),
#'   partial.values2 = c(4, 200, 3))
#' 
#' }
#' 
partial <- partial.rfsrc
get.partial <- function (partial.length) {
  ## Convert partial option into native code parameter.
  if (!is.null(partial.length)) {
    if (partial.length > 0) {
      bits <- 2^14
    }
      else if (partial.length == 0) {
        bits <- 0
      }
        else {
          stop("Invalid choice for 'partial.length' option:  ", partial.length)
        }
  }
    else {
      stop("Invalid choice for 'partial.length' option:  ", partial.length)
    }
  return (bits)
}
get.type <- function (family, partial.type) {
  if (family == "surv") {
    ## The native code interprets "rel.freq" as "mort".  The R-side
    ## handles the difference downstream after native code exit.
    if (partial.type == "rel.freq") {
      partial.type <- "mort"
    }
    ## Warning:  Hard coded in global.h
    type <- match(partial.type, c("mort", "chf", "surv"))
  }
    else if (family == "surv-CR") {
      ## Warning:  Hard coded in global.h
      type <- match(partial.type, c("years.lost", "cif", "chf"))
    }
      else {
        type <- 0
      }
  if (is.na(type)) {
    stop("Invalid choice for 'partial.type' option:  ", partial.type)
  }
  return (type)
}
get.oob <- function (oob) {
  ## Convert forest option into native code parameter.
  if (!is.null(oob)) {
    if (oob == TRUE) {
      oob <- 2^1
    }
      else if (oob == FALSE) {
        oob <- 2^0
      }
        else {
          stop("Invalid choice for 'oob' option:  ", oob)
        }
  }
    else {
      stop("Invalid choice for 'oob' option:  ", oob)
    }
  return (oob)
}
