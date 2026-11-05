FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY QrBackend.csproj ./
RUN dotnet restore
COPY . ./
RUN dotnet publish -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
# Volume ilk bağlandığında bu klasörün sahipliğini alır, app kullanıcısı anahtar yazabilsin diye.
RUN mkdir -p /home/app/.aspnet/DataProtection-Keys && chown -R app:app /home/app/.aspnet
COPY --from=build /app/publish ./
USER app
EXPOSE 5289
ENTRYPOINT ["dotnet", "QrBackend.dll"]
