FROM node:20-alpine
WORKDIR /app
COPY package.json proxy.js ./
EXPOSE 8080
CMD ["node", "proxy.js"]
