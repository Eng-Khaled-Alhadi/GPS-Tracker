# Stage 1: Build Flutter Web
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app

# Build arguments for dynamic server host
ARG SERVER_HOST=176.45.55.56
ENV SERVER_HOST=$SERVER_HOST

# Enable web support & fetch dependencies
RUN flutter config --enable-web
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy all source files and build for web
COPY . .
RUN flutter build web --release --dart-define=SERVER_HOST=$SERVER_HOST


# Stage 2: Serve Flutter Web with Nginx
FROM nginx:alpine
RUN rm -rf /usr/share/nginx/html/*
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]

