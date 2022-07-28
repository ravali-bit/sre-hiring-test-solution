FROM node:12-alpine

RUN mkdir -p /home/ubuntu/app/node_modules && chown -R node:node /home/ubuntu/app

WORKDIR /home/ubuntu/app

COPY package*.json ./

USER node

RUN npm install

COPY --chown=node:node . .

EXPOSE 3000

CMD [ "node", "app.js" ]
