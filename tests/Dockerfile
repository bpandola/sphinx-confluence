FROM ubuntu:14.04

RUN locale-gen en_US.UTF-8

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

RUN echo 'deb http://ppa.launchpad.net/fkrull/deadsnakes/ubuntu trusty main' >> /etc/apt/sources.list.d/python.list \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys DB82666C \
    && apt-get update -q \
    && apt-get install -y curl git \
        python2.7 python2.7-dev libpython2.7-dev \
        python3.5 python3.5-dev libpython3.5-dev \
        python3.6 python3.6-dev libpython3.6-dev \
    && curl -fSL "https://bootstrap.pypa.io/get-pip.py" -o get-pip.py \
    && python2.7 get-pip.py \
    && python3.4 get-pip.py \
    && python3.5 get-pip.py \
    && python3.6 get-pip.py \
    && rm get-pip.py \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y make

RUN pip install tox