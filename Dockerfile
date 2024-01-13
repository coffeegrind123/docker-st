#docker build --no-cache -t sillytavern:latest .; docker run -it -p 8000:8000 --name "sillytavern" --rm sillytavern:latest
FROM node:19.1.0-alpine3.16

# Arguments
ARG APP_HOME=/home/node/app

# Install system dependencies
RUN apk add gcompat tini git

# Ensure proper handling of kernel signals
ENTRYPOINT [ "tini", "--" ]

# Create app directory
WORKDIR ${APP_HOME}

RUN git clone https://github.com/SillyTavern/SillyTavern /tmp/source

# Install app dependencies
RUN cp /tmp/source/package*.json /tmp/source/post-install.js ./
RUN \
  echo "*** Install npm packages ***" && \
  npm install && npm cache clean --force

# Bundle app source
RUN cp -r /tmp/source/* ./

RUN rm -rf /tmp/source

RUN mkdir public/user

# Copy default chats, characters and user avatars to <folder>.default folder
RUN \
  IFS="," RESOURCES="assets,backgrounds,user,context,instruct,QuickReplies,movingUI,themes,characters,chats,groups,group chats,User Avatars,worlds,OpenAI Settings,NovelAI Settings,KoboldAI Settings,TextGen Settings" && \
  \
  echo "*** Store default $RESOURCES in <folder>.default ***" && \
  for R in $RESOURCES; do mv "public/$R" "public/$R.default"; done || true && \
  \
  echo "*** Create symbolic links to config directory ***" && \
  for R in $RESOURCES; do ln -s "../config/$R" "public/$R"; done || true && \
  \
  rm -f "config.yaml" "public/settings.json" || true && \
  ln -s "./config/config.yaml" "config.yaml" || true && \
  ln -s "../config/settings.json" "public/settings.json" || true && \
  mkdir "config" || true

# Cleanup unnecessary files
RUN \
  echo "*** Cleanup ***" && \
  mv "./docker/docker-entrypoint.sh" "./" && \
  rm -rf "./docker" && \
  echo "*** Make docker-entrypoint.sh executable ***" && \
  chmod +x "./docker-entrypoint.sh" && \
  echo "*** Convert line endings to Unix format ***" && \
  dos2unix "./docker-entrypoint.sh"

RUN sed -i "s/securityOverride: false/securityOverride: true/" /home/node/app/default/config.yaml

RUN sed -i "s/whitelistMode: true/whitelistMode: false/" /home/node/app/default/config.yaml

RUN sed -i "s/listen: false/listen: true/" /home/node/app/default/config.yaml

EXPOSE 8000

CMD [ "./docker-entrypoint.sh" ]
