FROM mcr.microsoft.com/powershell:7.0.1-ubuntu-16.04
LABEL maintainer="Matthew Kelly (Badgerati)"
RUN mkdir -p /usr/local/share/powershell/Modules/Pode
COPY ./pkg/ /usr/local/share/powershell/Modules/Pode