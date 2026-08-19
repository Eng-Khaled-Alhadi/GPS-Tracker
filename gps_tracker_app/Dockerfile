# Stage 1: Build Flutter Web
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app

# Enable web support & fetch dependencies
RUN flutter config --enable-web
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copy all source files and build for web
COPY . .
RUN flutter build web --release

# Stage 2: Serve Flutter Web with Nginx
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]

