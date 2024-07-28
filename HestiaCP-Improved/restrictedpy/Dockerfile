FROM python:3.12-slim

ENV USER=container

# Create non-root user
RUN adduser --shell=/usr/sbin/nologin --disabled-password --gecos "" $USER && usermod -G $USER $USER

# Change work directory
WORKDIR /home/$USER

#Download app & move it to workdir inside docker
ADD --chmod=755 https://raw.githubusercontent.com/erikdemarco/gists/main/HestiaCP-Improved/restrictedpy/app.py .

RUN pip install flask yfinance[nospam,repair]

# Bundle app source
COPY . .

EXPOSE 5001

# Run as user
USER $USER

CMD ["python3", "-I", "app.py"]
