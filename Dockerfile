FROM nginx:1.27-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY . /usr/share/nginx/html
RUN rm -rf /usr/share/nginx/html/deploy /usr/share/nginx/html/docs \
           /usr/share/nginx/html/Dockerfile /usr/share/nginx/html/CLAUDE.md \
           /usr/share/nginx/html/CNAME
EXPOSE 80
