To run docker containers with WSL2 on windows 11

update WSL and set WSL2 as the default version:\
```wsl.exe --update; wsl --set-default-version 2```

Then install docker desktop. To build and run the image:\
```docker build --no-cache -t docker-st:latest .; docker run -it -p 8000:8000 --name "docker-st" --rm docker-st:latest```
