using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyProduct("Pendrive de Recuperação")]
[assembly: AssemblyCompany("Yan Bento Monteiro")]
[assembly: AssemblyCopyright("Criado por Yan Bento Monteiro")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

// Extrai os arquivos embutidos no .exe para uma pasta temporária e roda o
// script PowerShell principal DENTRO deste processo (sem abrir powershell.exe).
// Assim a janela aparece na barra de tarefas com o ícone e o nome do programa.
static class Comum
{
    public const string Nome = "Pendrive de Recuperação";

    // arquivos: pares { nome do recurso, nome do arquivo extraído }
    public static void Executar(string subpasta, string[][] arquivos, string script)
    {
        try
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            string pasta = Path.Combine(Path.GetTempPath(), subpasta);
            Directory.CreateDirectory(pasta);
            Assembly asm = Assembly.GetExecutingAssembly();
            foreach (string[] a in arquivos)
            {
                using (Stream origem = asm.GetManifestResourceStream(a[0]))
                using (FileStream destino = File.Create(Path.Combine(pasta, a[1])))
                {
                    origem.CopyTo(destino);
                }
            }

            // Equivale ao "-ExecutionPolicy Bypass", valendo também para os
            // runspaces que o próprio script cria (trabalho em segundo plano)
            Environment.SetEnvironmentVariable("PSExecutionPolicyPreference", "Bypass");

            using (Runspace rs = RunspaceFactory.CreateRunspace(InitialSessionState.CreateDefault()))
            {
                rs.ApartmentState = ApartmentState.STA;
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();
                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddCommand(Path.Combine(pasta, script));
                    ps.Invoke();
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("Não foi possível iniciar.\n\n" + ex.Message, Nome, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
