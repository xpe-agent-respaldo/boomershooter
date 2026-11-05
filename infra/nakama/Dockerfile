FROM heroiclabs/nakama:3.30.0
COPY infra/nakama/start-nakama.sh /usr/local/bin/start-nakama.sh
COPY infra/nakama/modules /nakama/data/modules
RUN chmod +x /usr/local/bin/start-nakama.sh
ENTRYPOINT ["/usr/local/bin/start-nakama.sh"]
