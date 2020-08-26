FROM nvidia/cuda:10.2-cudnn7-runtime-centos7
MAINTAINER Michael Gorkow <michael.gorkow@sas.com>

# Add users and set passwords
RUN useradd -U -m sas && useradd -g sas -m cas
RUN echo "saspw" | passwd root --stdin && echo "saspw" | passwd sas --stdin && echo "saspw" | passwd cas --stdin

# set ulimit values
RUN echo "*     -     nofile     65536" >> /etc/security/limits.conf && echo "*     -     nproc      65536" >>/etc/security/limits.d/90-nproc.conf

# Install prereq packages
RUN yum -y update && yum install -y epel-release && yum install -y gcc libselinux-python wget git python-devel java-1.8.0-openjdk glibc libpng12 libXp libXmu numactl xterm initscripts which iproute sudo httpd mod_ssl && yum -y install openssl unzip openssh-clients bind-utils openssl-devel deltarpm libffi-devel net-tools sudo \
	&& yum -y groupinstall "Development Tools" \
	&& yum clean all

# Install ansible
RUN yum install --assumeyes python-setuptools python-devel openssl-devel python-pip tree automake python-six && pip install ansible==2.7; \
	yum install --assumeyes python

# Ansible known hosts
RUN mkdir ~/.ssh && touch ~/.ssh/known_hosts
RUN chmod --verbose 644 ~/.ssh/known_hosts

# Add deployment data zip to directory
RUN mkdir -p /opt/sas/installfiles
WORKDIR /opt/sas/installfiles
ADD SAS_Viya_deployment_data.zip /opt/sas/installfiles

# Get orchestration tool and install.  Then build and untar playbook
RUN wget https://support.sas.com/installation/viya/35/sas-mirror-manager/lax/mirrormgr-linux.tgz && tar zxfv mirrormgr-linux.tgz
RUN /opt/sas/installfiles/sas-orchestration build --platform redhat --architecture x64 --deployment-type programming --input SAS_Viya_deployment_data.zip && tar xvf SAS_Viya_playbook.tgz
WORKDIR /opt/sas/installfiles/sas_viya_playbook

# Deploy with ansible
RUN cp --verbose samples/inventory_local.ini . && \ 
        sed -i "/ notify/,+9d" roles/httpd-x64_redhat_linux_6-yum/tasks/configure-and-start.yml && \
	sed -i 's|VERIFY_DEPLOYMENT: true|VERIFY_DEPLOYMENT: false|' vars.yml && \
	ansible-playbook -i inventory_local.ini site.yml -vvv && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/cas/default/cas.hosts && \ 
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/cas/default/casconfig_deployment.lua && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/cas/default/cas.yml && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/cas/default/cas.hosts.tmp && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/batchserver/default/autoexec_deployment.sas && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/sysconfig/cas/default/sas-cas-deployment && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/sysconfig/cas/default/cas_grid_vars && \
	sed -i "s/$(hostname)/localhost/g" /opt/sas/viya/config/etc/workspaceserver/default/autoexec_deployment.sas && \
	sed -i "s/$(hostname)/localhost/g" /etc/httpd/conf.d/proxy.conf && \
	sed -i "s/#ServerName www.example.com:80/ServerName localhost/g" /etc/httpd/conf/httpd.conf

# Create homepage
RUN touch /var/www/html/index.html && printf "%s" "<h1>Welcome to SAS DeepLearn Docker</h1>" >> /var/www/html/index.html

#Install Anaconda
RUN yum install -y bzip2 ca-certificates \
    libglib2.0-0 libxext6 libsm6 libxrender1 \
    mercurial subversion graphviz

RUN wget https://repo.anaconda.com/archive/Anaconda3-2020.07-Linux-x86_64.sh -O ~/anaconda.sh && \
    /bin/bash ~/anaconda.sh -b -p /opt/conda && \
    rm ~/anaconda.sh

ENV PATH /opt/conda/bin:$PATH

#Create Anaconda Environment with Python 3.7 + Jupyter Lab + various packages
ENV PATH /opt/conda/bin:$PATH
RUN conda update --all  -y && conda install nb_conda_kernels -y
ADD jupyterlab_environments /opt/jupyterlab_environments
RUN curl -sL https://rpm.nodesource.com/setup_10.x | sudo bash - && sudo yum install -y nodejs
RUN for env_file in /opt/jupyterlab_environments/*; do conda env create -f $env_file; done

RUN jupyter labextension install @jupyter-widgets/jupyterlab-manager && \
	jupyter labextension install plotlywidget && \
	jupyter labextension install jupyter-leaflet

RUN mkdir -p /data/notebooks/

#Set environment variables
ENV JUPYTERLAB_PORT=8080
ENV JUPYTERLAB_NBDIR=/data/notebooks/

#Create ESP start script (setting LD_LIBRARY_PATH for SAS)
RUN echo -e '#!/bin/bash\n' \
            'httpd\n' \
            '/etc/init.d/sas-viya-all-services start\n' \
            'jupyter lab --port $JUPYTERLAB_PORT --ip 0.0.0.0 --allow-root --no-browser --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.notebook_dir=$JUPYTERLAB_NBDIR \n' \
            'while true \n' \
            'do \n' \
            'sleep 3600 \n' \
            'done' > /opt/sas/installfiles/start.sh
RUN chmod +x /opt/sas/installfiles/start.sh

# Calls start script (starts httpd and sas-viya-all-services, then sleeps)
CMD /opt/sas/installfiles/start.sh
