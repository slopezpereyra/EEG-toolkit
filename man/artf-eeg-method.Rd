% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/artifactor.R
\name{artf,eeg-method}
\alias{artf,eeg-method}
\title{Perform M-CAPA analysis on EEG data in a given range of seconds
and return results filtered by anomaly strength.}
\usage{
\S4method{artf}{eeg}(eeg, s = -1, e = -1, res = 1, alpha = 8, beta = 1)
}
\arguments{
\item{eeg}{An eeg object}

\item{s}{int First second of timespan to analyze}

\item{e}{int Last second of timespan to analyze}

\item{res}{int Resolution at which to perform analysis}

\item{alpha}{float Threshold of strength significance for
collective anomalies}

\item{beta}{float Threshold of strength significance for point anomalies}
}
\value{
An analysis object
}
\description{
Perform M-CAPA analysis on EEG data in a given range of seconds
and return results filtered by anomaly strength.
}
