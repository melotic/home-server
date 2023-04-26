use crate::eyre::eyre;
use azure_identity::DefaultAzureCredential;
use azure_security_keyvault::prelude::*;
use clap::{command, Parser, Subcommand};
use color_eyre::{eyre, owo_colors::OwoColorize, Result};
use futures::{future, stream::StreamExt};
use std::{sync::Arc, time::Instant};
use tokio::{
    fs::File,
    io::{AsyncReadExt, AsyncWriteExt},
};
use url::Url;

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
#[command(propagate_version = true)]
struct Cli {
    #[command(subcommand)]
    command: Command,

    vault_url: String,
}

#[derive(Subcommand)]
enum Command {
    Sync,
    Download,
}

fn get_kv_client(kv_url: &str) -> Result<SecretClient> {
    println!("🔐 Connecting to {}", "Azure Key Vault".blue());

    let creds = DefaultAzureCredential::default();
    let client = SecretClient::new(kv_url, Arc::new(creds))?;

    Ok(client)
}

#[tokio::main]
async fn main() -> Result<()> {
    color_eyre::install()?;

    let cli = Cli::parse();
    let client = get_kv_client(&cli.vault_url)?;
    let start = Instant::now();

    match cli.command {
        Command::Sync => sync_secrets(client).await,
        Command::Download => download_secrets(client).await,
    }?;

    let duration = start.elapsed();

    println!("⏱️ Done in {:.2?}", duration.bold().cyan());

    Ok(())
}

async fn sync_secrets(client: SecretClient) -> Result<()> {
    println!("📤 Uploading secrets to {}", "Azure Key Vault".blue());

    let mut env_file = File::open(".env").await?;
    let mut env_file_contents = String::new();
    env_file.read_to_string(&mut env_file_contents).await?;

    let mut tasks = Vec::new();

    for line in env_file_contents.lines() {
        let line = line.trim();

        if line.is_empty() {
            continue;
        }

        let mut parts = line.split('=');
        let key = parts.next().ok_or_else(|| eyre!("no key"))?;
        let value = parts.next().ok_or_else(|| eyre!("no value"))?;

        let client = client.clone();
        let key = key.replace('_', "-").to_owned();
        let value = value.to_owned();

        let task = tokio::task::spawn(async move {
            println!("Uploading {}", key.magenta());

            match client.set(&key, &value).await {
                Ok(_) => Ok(()),
                Err(e) => Err(eyre!("failed to upload {}: {}", key.magenta(), e)),
            }
        });

        tasks.push(task);
    }

    let secrets = future::try_join_all(tasks).await?;
    println!("{} Uploaded {} secrets", "✔️".green().bold(), secrets.len());

    Ok(())
}

async fn download_secrets(client: SecretClient) -> Result<()> {
    println!("📥 Downloading secrets from {}", "Azure Key Vault".blue());

    let mut stream = client.list_secrets().into_stream();
    let mut tasks = Vec::new();

    while let Some(secrets) = stream.next().await {
        let secrets = secrets?;
        println!("Found {} secrets", secrets.value.len());

        for id in secrets.value.iter().map(|x| &x.id) {
            let client = client.clone();
            let id = id.to_owned();

            let task = tokio::task::spawn(async move {
                let url = Url::parse(&id)?;
                let secret_name = url
                    .path_segments()
                    .ok_or_else(|| eyre!("got an invalid secret id"))?
                    .last()
                    .ok_or_else(|| eyre!("no path segments"))?;

                println!("Fetching {}", secret_name.magenta());

                let secret = match client.get(secret_name).await {
                    Ok(s) => s.value,
                    Err(e) => return Err(eyre!("failed to get secret: {}", e)),
                };

                Ok((secret_name.to_string(), secret))
            });

            tasks.push(task);
        }
    }

    let secret_kvs = future::try_join_all(tasks).await?;
    let mut env_file = File::create(".env").await?;
    let mut count = 0; //secret_kvs is moved into the loop

    for secret_kv in secret_kvs {
        let (secret_name, secret_value) = secret_kv?;
        let secret_name = secret_name.replace('-', "_");

        env_file
            .write_all(format!("{secret_name}={secret_value}\n").as_bytes())
            .await?;

        count += 1;
    }

    println!("\n{} Downloaded {} secrets", "✔️".green().bold(), count);

    Ok(())
}
