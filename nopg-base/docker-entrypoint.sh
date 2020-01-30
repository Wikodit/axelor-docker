#!/usr/bin/env bash
set -e

start_nginx() {
	local conf=nginx.conf
	[ -e /etc/nginx/certs/nginx.crt -a \
	  -e /etc/nginx/certs/nginx.key -a \
	  -e /etc/nginx/certs/dhparam.pem ] && conf=nginx-ssl.conf
	envsubst '$NGINX_HOST $NGINX_PORT' < /etc/nginx/conf.d.templates/${conf} > /etc/nginx/conf.d/default.conf
	service nginx start
}

start_tomcat() {
	if [ -f "$CATALINA_BASE/app.properties" ]; then
		JAVA_OPTS="-Daxelor.config=$CATALINA_BASE/app.properties $JAVA_OPTS" gosu tomcat tomcat run
	else
		gosu tomcat tomcat run
	fi
}

prepare_app() {

	# ensure tomcat specific dirs exist
	mkdir -p /var/log/tomcat
	mkdir -p $CATALINA_BASE/{conf,temp,webapps}

	# ensure custom upload dir exists
	mkdir -p $AXELOR_UPLOAD_DIR

	# prepare tomcat base
	if [ ! -f $CATALINA_BASE/conf/server.xml ]; then
		mkdir -p $CATALINA_BASE/{conf,temp,webapps}
		cp $CATALINA_HOME/conf/tomcat-users.xml $CATALINA_BASE/conf/
		cp $CATALINA_HOME/conf/logging.properties $CATALINA_BASE/conf/
		cp $CATALINA_HOME/conf/server.xml $CATALINA_BASE/conf/
		cp $CATALINA_HOME/conf/web.xml $CATALINA_BASE/conf/
		sed -i 's/directory="logs"/directory="\/var\/log\/tomcat"/g' $CATALINA_BASE/conf/server.xml
		sed -i 's/\${catalina.base}\/logs/\/var\/log\/tomcat/g' $CATALINA_BASE/conf/logging.properties
	fi

	# prepare config file and save it as app.properties
	(
		cd $CATALINA_BASE; \
		[ ! -e application.properties -a -e webapps/ROOT.war ] \
			&& jar xf webapps/ROOT.war WEB-INF/classes/application.properties \
			&& mv WEB-INF/classes/application.properties . \
			&& rm -rf WEB-INF;
		[ ! -e app.properties -a -e application.properties ] \
			&& cp application.properties app.properties \
			&& echo >> app.properties \
			&& echo "application.mode = prod" >> app.properties \
			&& echo "db.default.url = jdbc:postgresql://$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB" >> app.properties \
			&& echo "db.default.user = $POSTGRES_USER" >> app.properties \
			&& echo "db.default.password = $POSTGRES_PASSWORD" >> app.properties \
			&& echo "file.upload.dir = $AXELOR_UPLOAD_DIR" >> app.properties;
		exit 0;
	)

	# ensure proper permissions
	( chown -hfR $TOMCAT_USER:adm /var/log/tomcat || exit 0 )
	( chown -hfR $TOMCAT_USER:$TOMCAT_GROUP $CATALINA_BASE || exit 0 )
	( chown -hfR $TOMCAT_USER:$TOMCAT_GROUP $AXELOR_UPLOAD_DIR || exit 0 )

	# copy static files in a separate directory for nginx
	(
		cd $CATALINA_BASE/webapps; \
		[ ! -d static -a -e ROOT.war ] \
			&& mkdir -p static \
			&& cd static \
			&& jar xf ../ROOT.war css js img ico lib dist partials \
			&& cd .. \
			&& chown -R tomcat:nginx static;
		exit 0;
	)
}

if [ "$1" = "start" ]; then
	shift
	prepare_app
	start_nginx
	start_tomcat
fi

# Else default to run whatever the user wanted like "bash"
exec "$@"
