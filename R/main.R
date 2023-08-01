#' Class providing object with methods for EEG analysis, visualization, and manipulation.
#'
#' @docType class
#' @importFrom R6 R6Class
#' @export
#' @return Object of \code{\link{R6Class}} with methods for EEG analysis,
#' visualization and manipulation.
#' @format \code{\link{R6Class}} object.
#' @field data Stores the EEG data in a data frame format (tibble by default).
#' @field signals Stores a data frame with information on the EEG signals, if a
#' `signals` file was provided on initialization.
#' @field canoms A data frame with all data pertaining to collective anomalies
#' (artifacts) found on the EEG. Empty by default and until artifact analysis is
#' performed.
#' @field panoms A data frame with all data pertaining to point anomalies
#' (artifacts) found on the EEG. Empty by default and until artifact analysis is
#' performed.
#' @field psd Power spectrum density data of this EEG. Empty by default and
#' until PSD is computed on the EEG.
#' @field fs Sampling frequency of the EEG.
#' @section Methods:
#' \describe{
#'   \item{\code{subset_by_seconds(s, e)}}{Subsets the EEG from second s to
#'   second e. Both \code{s} and \code{e} must be numeric values that exist in the `Time`
#'   column of the EEG data. Modification is performed inplace.}
#'   \item{\code{subset(s, e)}}{Subsets the EEG from epoch s to epoch e. The
#'   interval is inclusive. Modification is performed inplace.}
#'   \item{\code{resample(n)}}{Reduces the EEG data by removing on every
#'   \code{n} samples. This is a (very) brute resampling method and should only
#'   be used for the purpose of accelerating certain analyses, such as
#'   artifact detection.}
#'   \item{\code{low_pass(n)}}{Applies a low-pass Butterworth filter with a
#'   filter frequency \code{n} (in Hz).}
#'   \item{\code{high_pass(n)}}{Applies a high-pass Butterworth filter with a
#'   filter frequency \code{n} (in Hz).}
#'   \item{\code{bandpass(l, h)}}{Applies a bandpass Butterworth filter with
#'   filter frequencies \code{l} (lower bound) and \code{h} (upper bound) (in Hz).}
#'   \item{\code{plot_channel(channel)}}{Plots the ith signal in data, where i =
#'   \code{channel}}.
#'   \item{\code{plot}}{Plots the EEG data.}
#'   \item{\code{iplot}}{Draws an interactive plot of the EEG data.}
#'   \item{\code{plot}}{Plots the EEG data.}
#'   \item{\code{drop_epochs(epochs, epoch = 30)}}{Given a list `epochs` of
#'   integer values, removes those epochs from the EEG data. The argument
#'   `epoch` determins how many seconds are understood to comprise an epoch and
#'   defaults to 30.}
#'   \item{\code{drop_subepochs(epochs, subepochs, epoch = 30)}}{Given numeric
#'   lists of \code{subepochs} and \code{epochs}, removes epoch/subepoch pairs from the
#'   EEG data. Elements in both lists are assumed to have an element-wise
#'   association, meaning that if \code{(e_1, ..., e_n), (s_1, ..., s_n)} are
#'   both lists, then epoch/subepoch pairs \code{(e_i, s_i)} are removed. The
#'   argument `epoch` is an integer determining how many seconds are understood
#'   to comprise an epoch (defaults to 30).}
#'   \item{\code{artf(alpha = 8, beta = 1)}}{Performs direct artifact detection
#'   over the EEG data. \code{alpha, beta} are numeric significance thresholds
#'   for collective and point anomalies respectively.}
#'   \item{\code{artf_stepwise(step_size = 30, alpha=8)}}{Performs stepwise
#'   artifact detection over the EEG data, by steps of \code{step_size} seconds.
#'   \code{alpha} is the significance threshold for collective anomalies.}
#'   \item{\code{get_contaminated_channels}}{Returns a vector with all EEG
#'   channels found to contain artifacts.}
#'   \item{\code{plot_artifacts(size = 0.2)}}{Plots EEG data with artifacts
#'   represented by red points of a certain \code{size}.}
#'   \item{\code{sfilter(x, f = minmax_normalization)}}{After normalizing
#'   artifact strength with a normalization function \code{f}, filters out all
#'   artifacts of strength lesser than \code{x}.}
#'   \item{\code{artf_reject()}}{Returns an artifact rejected copy of this EEG.}
#'   \item{\code{spectrogram(channel, max_freq = 30, freq = 4)}}{Plots the
#'   spectrogram of a given \code{channel}. \code{freq} is the resolution of the
#'   plot.}
#'   \item{\code{compute_psd()}}{Computes the power spectrum of this EEG and
#'   sotres it on the psd field.}
#'   \item{\code{plot_psd(xlim = 250)}}{Plots the PSD of this EEG.}
#'   \item{\code{iplot_psd(xlim)}}{Produces an interactive plot of the PSD.}}
EEG <- R6::R6Class("EEG", list(
    data = tibble::tibble(),
    signals = tibble::tibble(),
    canoms = tibble::tibble(),
    panoms = tibble::tibble(),
    psd = tibble::tibble(),
    spindles = tibble::tibble(),
    fs = 0,

    initialize = function(data_file, signals_file = NULL) {
        data <- readr::read_csv(data_file)
        if (!is.null(signals_file)) {
            signals <- readr::read_csv(signals_file)
            colnames(data)[-1] <- signals$Label %>%
                stringr::str_remove("EEG ") %>%
                stringr::str_remove("EOG")
        } else {
            signals <- tibble::tibble()
        }
        self$data <- data
        self$signals <- signals
        self$fs <- self$get_fs()
    },

    subset_by_seconds = function(s, e) {
        s_ind <- which(self$data$Time == s)
        e_ind <- which(self$data$Time == e)

        if (identical(s_ind, integer(0)) || identical(e_ind, integer(0))) {
            stop("You have not provided valid time bounds. Are you sure those
                 values exist?")
        }
        self$data <- self$data[s_ind:e_ind, ]
    },

    subset = function(s, e, epoch = 30) {
        df <- self$data %>%
            set_epochs(epoch) %>%
            dplyr::filter(Epoch %in% c(s:e))
        self$data <- df %>% select(-c("Epoch"))
    },

    resample = function(n) {
        self$data <- self$data[seq(1, nrow(self$data), n), ]
        self$fs <- self$get_fs()
    },

    get_fs = function() {
        delta_t <- self$data$Time[2] - self$data$Time[1]
        return(1 / delta_t)
    },

    vlow_pass = function(vec, n, fs) {
        wpass <- n / (fs / 2) # Nyquist
        but <- gsignal::butter(5, wpass, "low", output = "Sos")
        low_pass <- gsignal::filter(but, unlist(vec))
        return(low_pass)
    },

    vhigh_pass = function(vec, n, fs) {
        wpass <- n / (fs / 2) # Nyquist
        but <- gsignal::butter(5, wpass, "high", output = "Sos")
        high_pass <- gsignal::filter(but, unlist(vec))
        return(high_pass)
    },

    vbandpass = function(vec, l, h, fs) {
        fpass <- c(l, h)
        wpass <- fpass / (fs / 2) # Nyquist
        but <- gsignal::butter(5, wpass, "pass", output = "Sos")
        pass <- gsignal::filter(but, unlist(vec))
        return(pass)
    },

    low_pass = function(n) {
        filt_df <- apply(self$data[-1],
            MARGIN = 2,
            FUN = function(x) self$vlow_pass(x, n, self$fs),
            simplify = FALSE
        ) %>%
            tibble::as_tibble() %>%
            tibble::add_column(Time = self$data$Time,
                                .before = colnames(self$data)[2])
        self$data <- filt_df
    },


    high_pass = function(n) {
        filt_df <- apply(self$data[-1],
            MARGIN = 2,
            FUN = function(x) self$vhigh_pass(x, n, self$fs),
            simplify = FALSE
        ) %>%
            tibble::as_tibble() %>%
            tibble::add_column(Time = self$data$Time,
                                .before = colnames(self$data)[2])
        self$data <- filt_df
    },


    bandpass = function(l, h) {
        filt_df <- apply(self$data[-1],
            MARGIN = 2,
            FUN = function(x) self$vbandpass(x, l, h, self$fs),
            simplify = FALSE
        ) %>%
            tibble::as_tibble() %>%
            tibble::add_column(Time = self$data$Time,
                                .before = colnames(df)[2])
        self$data <- filt_df
    },


    plot_channel = function(channel) {
        y <- self$data[-1][channel]
        p <- self$data %>%
            dplyr::mutate(Time = lubridate::as_datetime(Time)) %>%
            ggplot2::ggplot(
                ggplot2::aes(
                    Time,
                    unlist(y)
                )
            ) +
            ggplot2::geom_line() +
            ggplot2::scale_x_datetime(date_labels = "%H:%M:%S") +
            ggplot2::xlab("") +
            ggplot2::ylab(colnames(self$data[-1][channel]))

        return(p)
    },

    plot = function() {
        plots <- list()
        for (channel in 1:(ncol(self$data) - 1)) {
            p <- self$plot_channel(channel)
            plots[[channel]] <- p
        }

        return(cowplot::plot_grid(plotlist = plots, align = "v", ncol = 1))
    },

    iplot = function() {
        plots <- list()
        plots[[1]] <- plotly::plot_ly(
            self$data,
            type = "scatter",
            mode = "lines"
        ) %>%
            plotly::add_trace(
                x = ~Time, y = unlist(self$data[, 2]),
                name = colnames(self$data)[2]
            )
        for (i in 3:length(self$data)) {
            fig <- plotly::plot_ly(
                self$data,
                type = "scatter",
                mode = "lines"
            ) %>%
                plotly::add_trace(
                    x = ~Time, y = unlist(self$data[, i]),
                    name = colnames(self$data)[i]
                )
            plots[[i - 1]] <- fig
        }
        return(plotly::subplot(
            plots,
            nrows = length(plots),
            shareX = TRUE
        ))
    },


    drop_epochs = function(epochs, epoch = 30) {
        df <- self$data %>% set_epochs(epoch)
        df <- droplevels(df[!df$Epoch %in% epochs, ])[-2]
        self$data <- df %>% select(-c("Epoch"))
    },

    drop_subepochs = function(epochs, subepochs, epoch = 30) {
        contaminated <- as.factor(paste(epochs, subepochs))
        df <- self$data %>% set_epochs(epoch, subepochs = TRUE)

        df <- df %>% tibble::add_column(
            Pairs = as.factor(paste(df$Epoch, df$Subepoch)),
            .after = "Subepoch"
        )
        df <- droplevels(df[!df$Pairs %in% contaminated, ])[-c(2, 3, 4)]
        self$data <- df
    },

    # ---- Artifact related functions

    artf = function(alpha = 8, beta = 1) {
        print("Starting artifact analysis. This may take a couple of minutes...")
        start_time <- Sys.time()
        analysis <- anomaly::capa.mv(self$data[-1], type = "mean")
        canoms <- anomaly::collective_anomalies(analysis) %>%
            dplyr::filter(mean.change >= alpha) %>%
            set_timevars(data = self$data) %>%
            tibble::as_tibble()
        panoms <- anomaly::point_anomalies(analysis) %>%
            dplyr::filter(strength >= beta) %>%
            set_timevars(data = self$data) %>%
            tibble::as_tibble()
        end_time <- Sys.time()
        print(paste(
            "Analysis took ",
            (end_time - start_time)
        ))
        self$canoms <- canoms
        self$panoms <- panoms
    },

    artf_stepwise = function(step_size = 30, alpha = 8, type = "mean") {
        print("Starting analysis. This may take a couple of minutes...")
        # Set epochs for grouping
        t <- set_epochs(self$data, epoch = step_size) %>% head(-1)
        mps <- self$fs * step_size # measures per step
        grouped <- dplyr::group_by(t[-1], Epoch) %>%
            dplyr::group_map(~ anomaly::capa.mv(x = .x, type = type))
        canoms <- grouped %>%
            lapply(function(x) {
                        anomaly::collective_anomalies(x) %>%
                        dplyr::filter(mean.change >= alpha)
        })
        panoms <- grouped %>% lapply(function(x) anomaly::point_anomalies(x))

        canoms <- mapply(function(x, y) {
                            x %>% dplyr::mutate(
                                                start = start + mps * (y - 1),
                                                end = end + mps * (y - 1))
                            },
            canoms, seq_along(canoms),
            SIMPLIFY = FALSE) %>%
            dplyr::bind_rows() %>%
            set_timevars(self$data)

        panoms <- mapply(function(x, y) {
                         x %>% mutate(location = location + mps * (y - 1))
                        },
                        panoms, seq_along(panoms),
                        SIMPLIFY = FALSE) %>%
                dplyr::bind_rows() %>%
                set_timevars(self$data)

        end_time <- Sys.time()
        self$canoms <- canoms
        self$panoms <- panoms
    },

    get_contaminated_channels = function() {
        chans <- union(
            unique(self$canoms$variate),
            unique(self$panoms$variate)
        )
        return(chans)
    },

    set_plot_data = function(chan) {
        data <- self$data # For shorter lines in what follows
        canoms <- dplyr::filter(self$canoms, variate == chan)
        panoms <- dplyr::filter(self$panoms, variate == chan)
        # Get all indexes between start and end of canoms
        locations <- mapply(function(x, y) x:y, canoms$start, canoms$end)
        # Unite with point anomalies
        locations <- union(unlist(locations), unlist(panoms$location)) %>%
                    as.integer()
        time_of_anomalies <- lubridate::as_datetime(unlist(data[locations, 1]))
        values <- unlist(data[locations, chan + 1])
        df <- tibble::tibble(A = time_of_anomalies, B = values)
        return(df)
    },

    plot_channel_artifacts = function(chan, size = 0.2) {
        df <- self$set_plot_data(chan)
        eeg <- self$plot_channel(channel = chan)
        p <- eeg +
            ggplot2::geom_point(
                data = df, ggplot2::aes(A, B),
                inherit.aes = FALSE, color = "red",
                size = size
            )
        return(p)
    },

    plot_artifacts = function(size = 0.2) {
        plots <- list()
        channels <- self$get_contaminated_channels()
        for (channel in channels) {
            p <- self$plot_channel_artifacts(channel, size)
            plots[[channel]] <- p
        }
        return(cowplot::plot_grid(plotlist = plots, align = "v", ncol = 1))
    },


    sfilter = function(x, f = minmax_normalization) {
        self$canoms$mean.change <- f(self$canoms$mean.change)
        self$panoms$strength <- f(self$panoms$strength)
        self$canoms <- self$canoms %>% dplyr::filter(mean.change >= x)
        self$panoms <- self$panoms %>% dplyr::filter(strength >= x)
    },

    get_contaminated_epochs = function() {
        l <- list(self$canoms, self$panoms)
        i <- which(lapply(l, nrow) == 0)
        # If both data frames have length 0
        if (length(i) > 1) {
            stop("Empty analysis error")
        }
        # If both data frames are non-empty
        if (identical(i, integer(0))) {
            a <- canoms_avg_epoch_strength(self$canoms)
            b <- panoms_avg_epoch_strength(self$panoms)
            return(dplyr::full_join(a, b))
        }
        # If only one is non-empty
        if (i == 1) {
            return(panoms_avg_epoch_strength(self$panoms))
        }
        return(canoms_avg_epoch_strength(self$canoms))
    },

    artf_reject = function() {
        epoch_data <- self$get_contaminated_epochs()
        clone <- self$clone()
        clone$drop_subepochs(epoch_data$Epoch, epoch_data$Subepoch)
        clone$canoms <- clone$panoms <- tibble::tibble()
        return(clone)
    },

    # --- PSD ---


    spectrogram = function(channel, max_freq = 30, freq = 4) {
        rsleep::spectrogram(unlist(self$data[-1][channel]),
                            sRate = self$fs, maxFreq = max_freq,
                            freq = freq)
    },

    channel_psd = function(channel) {
        welch <- gsignal::pwelch(as.matrix(self$data[-1][channel]), fs = self$fs)
        psd <- welch$spec %>%
            apply(log10, MARGIN = 2) %>%
            tibble::as_tibble()
        psd$Fqc <- welch$freq
        return(psd)
    },

    compute_psd = function() {
        pwelch <- gsignal::pwelch(as.matrix(self$data[-1]), fs = self$fs)
        psd <- pwelch$spec %>%
            apply(log10, MARGIN = 2) %>%
            tibble::as_tibble()
        psd$Fqc <- pwelch$freq
        self$psd <- psd
    },

    plot_psd = function(xlim = 250) {
        tall <- reshape2::melt(self$psd, id.vars = "Fqc")
        p <- ggplot2::ggplot(tall, ggplot2::aes(Fqc, value, col=variable)) +
            ggplot2::geom_line() +
            ggplot2::xlim(c(0, xlim))
        return(p)
    },

    iplot_psd = function(xlim = 250) {
        psd <- reshape2::melt(self$psd, id.vars = "Fqc")
        fig <- plotly::plot_ly(
            psd,
            type = "scatter",
            mode = "lines"
        ) %>%
            plotly::add_trace(
                x = ~Fqc, y = ~value, color = ~variable
            ) %>%
            layout(
                xaxis = list(
                    title = "Frequency in Hz",
                    zeroline = F,
                    range = c(0, xlim)
                ),
                yaxis = list(
                    title = "log10 Spectrum",
                    zeroline = F
                )
            )
        return(fig)
    },

    spindle_detection = function(channel = 0,
                                 method = "sigma_index",
                                 filter = TRUE) {
        if (method == "sigma_index") {
            f <- sigma_index
            threshold <- 4.5
        }else if (method == "rsp") {
            f <- relative_spindle_power
            threshold <- 0.22
        }else {
            stop("Invalid spindle detection method. `method` argument should be:
            'rsp': for Relative Spindle Power detection, or
            'sigma_index': for Sigma Index detection.")
        }
        if (channel != 0) {
            data <- self$data[c(1, channel)] %>% window_eeg_data(1)
        }else {
            data <- self$data %>% window_eeg_data(1)
        }
        result <- data %>%
            group_by(Group = Windows) %>%
            summarize(across(-c(Time, Windows), \(x) f(x, fs = self$fs))) %>%
            mutate(Group = as.numeric(str_extract(Group, "\\d+\\.?\\d*?(?=,)"))) %>%
            rename(Second = Group) %>%
            na.omit()
        if (filter) {
            result <- result %>%
                filter(across(-Second, ~ . > threshold)
                %>% rowSums() > 0) %>%
                mutate(across(-Second, ~ ifelse(. < threshold, 0, .))) %>%
                select(where(~ any(. != 0)))
        }
        self$spindles <- result
    },


    plot_spindle_distribution = function(channel = 0,
                                         time_axis = "epoch",
                                        xbins = 10,
                                        ybins = 10,
                                        from = 0) {
        time_resolution <- c(second = 1 / 60,
                            minute = 1 / (60 ^ 2),
                            hour = 1 / (60 ^ 3),
                            epoch = 1 / 30)
        data <- self$spindles
        if (channel == 0) {
            ylabel <- "Cumulative Index Score"
            y <- rowSums(data[, !colnames(data) %in% c("Second")])
            plot_title <- "Cumulative spindle distribution over time"
        }else{
            y <- data[[channel + 1]]
            ylabel <- "Index Score"
            plot_title <- paste(colnames(data)[channel + 1],
                                ": Spindle distribution over time",
                                sep = "")
        }

        fig <- plot_ly(self$spindles,
            x = ~(Second * time_resolution[time_axis]),
            y = y)
        fig <- fig %>%
          add_histogram2d(
                nbinsx = xbins,
                nbinsy = ybins,
                ybins = list(start = from)
            ) %>%
          layout(
            title = plot_title,
            xaxis = list(title = paste(time_axis, "s", sep = "")),
            yaxis = list(title = ylabel)
          )
        return(fig)
    }
    )
)