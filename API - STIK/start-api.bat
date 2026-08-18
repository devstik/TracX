@echo off
echo 🔄 Iniciando a API Stik com Docker...

docker run -p 5000:5000 ^
  -e PGHOST=shortline.proxy.rlwy.net ^
  -e PGPORT=19369 ^
  -e PGDATABASE=railway ^
  -e PGUSER=postgres ^
  -e PGPASSWORD=PqEWJhSxpSLBuuTUqfZYFdbgvxoWoKVA ^
  stik-api

pause
