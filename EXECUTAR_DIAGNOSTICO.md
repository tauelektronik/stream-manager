# Como Executar o Diagnóstico

## Opção 1: Via PowerShell (Windows)

Abra o **PowerShell** e execute:

```powershell
ssh root@186.233.119.88 "curl -sSL https://raw.githubusercontent.com/tauelektronik/stream-manager/main/diagnostico.sh | bash"
```

Quando pedir a senha, digite: `Conect89123@`

O resultado aparecerá na tela. **Copie tudo** e envie para análise.

---

## Opção 2: Salvar resultado em arquivo

```powershell
ssh root@186.233.119.88 "curl -sSL https://raw.githubusercontent.com/tauelektronik/stream-manager/main/diagnostico.sh | bash" > diagnostico-resultado.txt 2>&1
```

Depois abra o arquivo `diagnostico-resultado.txt` e envie o conteúdo.

---

## Opção 3: Conectar e executar manualmente

```powershell
# 1. Conectar
ssh root@186.233.119.88

# 2. Executar diagnóstico
curl -sSL https://raw.githubusercontent.com/tauelektronik/stream-manager/main/diagnostico.sh | bash

# 3. Copiar resultado e enviar
```

---

## Se der erro "ssh não encontrado"

Instale o OpenSSH no Windows:
1. Vá em **Configurações** > **Aplicativos** > **Recursos Opcionais**
2. Clique em **Adicionar um recurso**
3. Procure por **OpenSSH Cliente**
4. Instale e reinicie o PowerShell
