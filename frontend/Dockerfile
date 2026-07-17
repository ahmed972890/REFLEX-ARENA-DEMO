# ---- build stage: compile the Vite bundle ----
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# ---- runtime stage: unprivileged nginx serving static files + /api proxy ----
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
# Overridden per environment: compose → http://backend:8000, k8s → the backend Service.
ENV BACKEND_URL=http://localhost:8000
EXPOSE 8080
