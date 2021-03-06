#'  Generates dataframe with all dependencies needed to install a package, in the order they will be loaded
#'
#'@param pkg character string, name of target package to load (and install if needed), 
#'@param date character string  (yyyy-mm-dd), or date value, with the date which determines the 
#'version of the package, and all dependencies, to be loaded (and installed if needed).
#'@param include.suggests logical, defaults to `FALSE`. When set to `TRUE`, includes
#'   dependencies classified in the DESCRIPTION file as `suggested`.
#'@param force.source logical (defaults to `FALSE`). When set to `TRUE`, will not attempt 
#'   installing binary from CRAN or MRAN and instead download source file and install it.
#'@return a dataframe with all packages that need to be installed, their version , whether they are installed, where 
#'to obtain them if not locally available (CRAN vs MRAN), which date to use for MRAN, 
#'installation time from source (in seconds), and local path for storage
#' @examples
#' \dontrun{
#' get.snowball("rio", "2020-07-12")
#'}
#' @export


get.snowball <- function(pkg, date, include.suggests = FALSE, force.source = FALSE) {

  # 1) Get dependencies
  dep12 <- get.all.dependencies(pkg, date, include.suggests = include.suggests)

  # 2) process dep12  (topographical sort) to get order of installation
  k <- 0 # counter of iterations attempting to sort
  indep <- c()
  # In each loop we take all dependencies without dependencies and add them to the sequence of installation
  # Do until all dependencies have been assigned an order (so dep12 is empty)
  while (nrow(dep12) > 0) {
    k <- k + 1
    indep.rows <- !(dep12$dep2 %in% dep12$pkg) ## Find dependencies without dependencies  TRUE/FALSE vector
    # Add those dependencies to the list of independencies
    indepk <- unique(as.character(dep12$dep2[indep.rows]))
    indep <- c(indep, indepk)
    # Drop those rows from both
    dep12 <- dep12[!indep.rows, ]
    # Safety valve in case loop impossible to end
    if (k == 50000) {
      break
    }
  }
  # 3) Add pkg at the end
  snowball.pkg <- c(indep, pkg)

  # 4) Get the version of each package
  snowball.vrs <- vapply(snowball.pkg, get.version, date, FUN.VALUE = character(1)) 
  snowball.pkg_vrs <- paste0(snowball.pkg, "_", snowball.vrs)

  # 5 Snowball table, with installed | CRAN | MRAN | TARBALL | INSTALLATION TIME

  # - Install from CRAN if possible
  # - else, install from MRAN if possible
  # - else, install from source

  snowball.installed <- mapply(is.pkg_vrs.installed, snowball.pkg, snowball.vrs) # 5.1 Installed?  TRUE/FALSE

  # Vector with paths
  snowball.installation.path <- mapply(get.pkg_search_paths, snowball.pkg, snowball.vrs)

  # No need to find the locations if everything is already installed. This also
  # allows us to run offline in easy cases
  if (all(snowball.installed)) {
    return(
      data.frame(
        "pkg" = snowball.pkg,
        "vrs" = snowball.vrs,
        "pkg_vrs" = snowball.pkg_vrs, # Identify pkg
        "installed" = TRUE, # Installed?
        "from" =  NA_character_, # Where to install from
        "MRAN.date" = NA_character_, # MRAN date, in case MRAN is tried
        "installation.time" = NA_real_, # time to install
        "installation.path" = snowball.installation.path,
        stringsAsFactors = FALSE
      )
    )
  }

  
  
  #if (max(toc("R")$Version) == get.rversion()) {
    snowball.CRAN <- snowball.pkg_vrs %in% get.current.packages("binary")$pkg_vrs
  #} else {
  #  snowball.CRAN <- rep_len(FALSE, length(snowball.pkg_vrs))
  #}
  snowball.MRAN.date <- as.Date(sapply(snowball.pkg_vrs, get.date.for.install.binary), origin = "1970-01-01") # 5.3 Binary date in MRAN?
  snowball.MRAN.date <- as.DateYMD(snowball.MRAN.date)

  # IF force.source==TRUE then all packages will come from source, else, figure out where from
  if (force.source) {
    snowball.from <- rep_len("source", length(snowball.pkg))
  } else {
    snowball.MRAN <- snowball.MRAN.date != "1970-01-01"
    snowball.from <- ifelse(snowball.MRAN, "MRAN", "source") # MRAN if available, if not source
    snowball.from <- ifelse(snowball.CRAN, "CRAN", snowball.from) # Replace MRAN if CRAN is available and using most recent version of R
  }

  # Installation time from source
  snowball.time <- round(mapply(get.installation.time, snowball.pkg, snowball.vrs), 0)

  # Adjust installation time
  adjustment <- 2.5 # install times in CRAN's page are systematically too long, this is an initial adjustment factor
  snowball.time <- pmax(round(snowball.time / adjustment, 0), 1)

  # data.frame()
  snowball <- data.frame(
    "pkg" = snowball.pkg,
    "vrs" = snowball.vrs,
    "pkg_vrs" = snowball.pkg_vrs, # Identify pkg
    "installed" = snowball.installed, # Installed?
    "from" = snowball.from, # Where to install from
    "MRAN.date" = snowball.MRAN.date, # MRAN date, in case MRAN is tried
    "installation.time" = snowball.time, # time to install
    "installation.path" = snowball.installation.path,
    stringsAsFactors = FALSE
  )


  return(snowball)
}
