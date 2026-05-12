FROM perl:5.38
WORKDIR /app
RUN cpanm Mojolicious
COPY app.pl setup_data.pl ./
RUN perl setup_data.pl
ENV PORT=8080
EXPOSE 8080
CMD ["perl", "app.pl", "daemon", "-l", "http://*:8080"]
