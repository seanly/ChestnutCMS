FROM seanly/toolset:oracle-jdk17 as backend-build

COPY ./ /code
WORKDIR /code

RUN ./mvnw -B -U clean package -DskipTests

ARG APP_NAME=chestnut-admin
ARG APP_VERSION=0.0.1
ENV SPRING_PROFILES_ACTIVE=prod

RUN mkdir -p /home/app; cd /home/app && \
    cp /code/chestnut-admin/target/chestnut-admin.jar chestnut-admin.jar && \
    java -Djarmode=layertools -Dspring.profiles.active=${SPRING_PROFILES_ACTIVE} -jar chestnut-admin.jar extract

FROM seanly/toolset:oracle-jdk17 as backend

WORKDIR /home/app

COPY --from=backend-build /home/app/dependencies/ ./  
COPY --from=backend-build /home/app/spring-boot-loader/ ./  
COPY --from=backend-build /home/app/snapshot-dependencies/ ./ 
COPY --from=backend-build /home/app/application ./   

ENV TZ="Asia/Shanghai" \
    SERVER_PORT=8090 \
    JVM_OPTS="-Xms2g -Xmx2g -Xmn512m -XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=256m" \
    JAVA_OPTS=""

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
	&& mkdir -p logs
    
VOLUME ["/home/app/logs","/home/app/uploadPath","/home/app/wwwroot_release","/home/app/_xy_member"]

EXPOSE $SERVER_PORT $NETTY_SOCKET_PORT

ENTRYPOINT ["sh","-c","java $JVM_OPTS $JAVA_OPTS org.springframework.boot.loader.JarLauncher"]


FROM seanly/toolset:nodejs-v16 as frontend-build

COPY ./ /code
WORKDIR /code/chestnut-ui

RUN npm install --registry=https://registry.npmmirror.com && \
    npm run build:prod

FROM seanly/appset:tengine-2.4.1 as frontend

COPY --from=frontend-build /code/chestnut-ui/dist/ /usr/share/nginx/html/
COPY --from=frontend-build /code/chestnut-ui/default.conf /usr/local/nginx/conf/vhosts/default.conf

WORKDIR /usr/share/nginx/html

FROM seanly/scratch as local

COPY --from=backend-build /code/chestnut-admin/target/chestnut-admin.jar /target/
COPY --from=frontend-build /code/chestnut-ui/dist/ /dist/
