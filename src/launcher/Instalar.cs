using System;
using System.Reflection;

[assembly: AssemblyTitle("Instalar Pendrive de Recuperação")]
[assembly: AssemblyDescription("Instala o Pendrive de Recuperação e cria os atalhos")]

// "Instalar Pendrive de Recuperação.exe": leva embutidos o instalador e o
// executável portátil, que é o que fica instalado na máquina.
static class Instalar
{
    [STAThread]
    static void Main()
    {
        Comum.Executar("PendriveRecuperacao_Instalador", new[] {
            new[] { "Instalador.ps1",          "Instalador.ps1" },
            new[] { "PendriveRecuperacao.exe", "Pendrive de Recuperação.exe" },
        }, "Instalador.ps1");
    }
}
