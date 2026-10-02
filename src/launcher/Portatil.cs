using System;
using System.Reflection;

[assembly: AssemblyTitle("Pendrive de Recuperação")]
[assembly: AssemblyDescription("Prepara pendrive para reparar a inicialização do Windows")]

// "Pendrive de Recuperação.exe": versão portátil, abre direto o Preparar Pendrive.
// Roda como administrador (admin.manifest), necessário para formatar o pendrive.
static class Portatil
{
    [STAThread]
    static void Main()
    {
        Comum.Executar("PendriveRecuperacao", new[] {
            new[] { "PrepararPendrive.ps1",     "PrepararPendrive.ps1" },
            new[] { "ColetarInicializacao.bat", "ColetarInicializacao.bat" },
            new[] { "RepararInicializacao.bat", "RepararInicializacao.bat" },
        }, "PrepararPendrive.ps1");
    }
}
