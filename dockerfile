FROM <docker hub name of the resulting base image, e.g. spacegravimetry/gmt>  AS builder
WORKDIR /builder
RUN git clone --recurse-submodules <github repo URL OR local directory, with software to dockerize>  . && rm -fr .git
RUN <additional dockerfile RUN commands when building the app image, always start with '&&', e.g. '&& make'; leave empty if not relevant> 
RUN chmod -R o+rX .

FROM <docker hub name of the resulting base image, e.g. spacegravimetry/gmt> 
LABEL Author "<email/contact/reference>"
LABEL app-repo "<github repo URL OR local directory, with software to dockerize> "
WORKDIR /<some name for this app>
VOLUME /iodir
ENTRYPOINT ["./entrypoint.sh"]
COPY --from=builder /builder/ ./

