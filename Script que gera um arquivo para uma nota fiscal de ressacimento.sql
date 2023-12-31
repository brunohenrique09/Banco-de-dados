/******************************************************************************
  Descrição: criar_procedure_usp_mng_GerarArquivoNotaFiscalRessarcimento
*******************************************************************************/
IF EXISTS (SELECT * FROM sysobjects WHERE [type] = 'P' AND [name] = 'usp_mng_GerarArquivoNotaFiscalRessarcimento')
BEGIN
	PRINT 'Removendo Procedure usp_mng_GerarArquivoNotaFiscalRessarcimento'
	DROP PROCEDURE usp_mng_GerarArquivoNotaFiscalRessarcimento
END
GO

PRINT 'Criando Procedure usp_mng_GerarArquivoNotaFiscalRessarcimento'
GO

  
CREATE PROCEDURE usp_mng_GerarArquivoNotaFiscalRessarcimento
As  
  
 Declare @ErrorMessage Nvarchar(Max);  
 Declare @ErrorSeverity Int;  
 Declare @ErrorState Int;  
  
 
 -- Abrindo a transação e utilizando o try pra controlar possiveis erros validação.
 -- Nesse bloco, especificamos onde o arquivo desse script será gerado, através da variavel  @str_PathGeracaoArquivo.
 -- É importante que a pasta criada esteja dentro do mesmo servidor que você está utilizando aqui no SQL, caso contrário, dará erro de permissão.
 
 
 Begin Try  
  
  Declare  
   @str_PathGeracaoArquivo Varchar(1000) = '\\MEU-SRV\Dados\teste', -- CAMINHO DO ARQUIVO
   @str_NomeCompletoArquivo Varchar(1000) = Null,  
   @str_InstanciaSQL Varchar(50) = @@ServerName,  
   @str_DataBase Varchar(128) = Db_Name(),  
   @int_IdMovimento Int = Null,  
   @int_NumeroDocumento Int = Null,  
   @str_CNPJEmpresa Nvarchar(18) = Null,  
   @str_SelectGerarArquivo Varchar(1000) = Null,  
   @int_ContadorLinha Int = Null,  
   @bit_PathExiste Bit = 0,  
   @bit_VerificaArquivoExiste Bit = 0,  
   @LineBreak Varchar(10) = Char(13) + Char(10);
   
  
  Set @str_PathGeracaoArquivo = Case Right(Rtrim(@str_PathGeracaoArquivo), 1)  
                  When '\'  
                   Then @str_PathGeracaoArquivo  
                  Else @str_PathGeracaoArquivo + '\'  
                 End  
  
  
  
  /*Verifica se o Diretório Informado existe*/  
  Exec usp_mng_ValidarPathExiste @str_PathGeracaoArquivo, @bit_PathExiste OutPut  
  
  If IsNull(@bit_PathExiste, 0) = 0  
   Begin  
    /***Se o diretório informado não for encontrado lança uma exceção***/  
    Set @ErrorMessage = 'Erro: O diretório (' + IsNull(@str_PathGeracaoArquivo, '') + ') não existe, ou o SQL Server não tem permissão para acessar';  
    Raiserror (@ErrorMessage, 16, 1);  
   End  
  /*Verifica se o Diretório Informado existe*/  
  
  Declare cur_NotaFiscal Cursor For  
  Select  
   a.IdMovimento,  
   a.NúmeroDocumento,  
   b.CGC  
  From  
   Mov_Estoque As a With (NoLock)  
    Inner Join  
   Tab_Empresa As b With (NoLock)  
     On a.IdEmpresa = b.IdEmpresa  
    Inner Join  
   Mov_Estoque_Detalhes As c With (NoLock)  
     On a.IdMovimento = c.IdMovimento  
    Inner Join  
   Tab_Estoque As d With (NoLock)  
     On c.IdItem = d.IdItem  
    Inner Join  
   NFEletronica As e With (NoLock)  
     On a.IdMovimento = e.fk_int_Idmovimento  

-- Nesse where é definido através das condições, que esse arquivo é uma Nota Fiscal de Ressacimento.
-- E  toda a estrutura dessa procedure, também foi feita pra atender uma unica marca.

Where  
   a.ClassificaçãoMovimento = 2  
      And a.IdCancelamento Is Null  
      And a.IdTipoMovimento <> 533
      And d.IdMarca = 1078        
      And Cast(a.DataMovimento As Date) = Cast(Getdate() As Date)   
      And e.int_cod_StatusResposta = 100  
      And Not Exists(Select 1 From Tab_GerarArquivoFarmaAutomatico As aa Where aa.int_idmovimento = a.IdMovimento And aa.bit_ArquivoGerado = 1 And aa.int_FarmaConfig = 0 And aa.int_enumFarmaLayouts = 0)  
  Group By  
   a.IdMovimento,  
   a.NúmeroDocumento,  
   b.CGC  
  Order By  
   a.Idmovimento  
  
  --Abrindo Cursor  
  Open cur_NotaFiscal  
   
  Fetch Next From cur_NotaFiscal Into @int_IdMovimento, @int_NumeroDocumento, @str_CNPJEmpresa;  
  
  -- Percorrendo linhas do cursor  
  While @@FETCH_STATUS = 0  
   Begin  
    Delete From tmp_GerarArquivoRetornoPedido Where int_idmovimento = @int_IdMovimento;  
      
    Set @str_SelectGerarArquivo = 'Select str_arquivo From ' + @str_DataBase + '..tmp_GerarArquivoRetornoPedido Where int_idmovimento = ' + Cast(IsNull(@int_IdMovimento, 0) As Varchar(10)) + ' Order By pk_int_tmp_gerararquivoretornopedido Asc';  
    
    
	-- A partir daqui, começamos a montar nosso arquivo que será um TXT, que posteriormente será lido pelo integrador.
	-- Toda a estrura do  código a baixo, é desenvolvida de acordo com os dados fornecidos pelo integrador, de acordo com a documentação do seu projeto.
	-- São separados vários sub selects , retornando os dados rerefentes a cada estrutura de dados solicitada no documento.
	-- O primeiro, cabecalho da nota fiscal
	-- O segundo, os dados da nota fiscal
	-- O terceiro, os totais da nota fiscal
	-- O quarto, os impostos contidos na nota fiscal
	-- O quinto, os intes que consta na nota fiscal
	-- O sexto,  é a linha verificadora, que identifica a quantidade de linhas que o arquivo tem, e a sua quantidade de itens.
	
	;With Cabecalho_Nota  
    As  
    (  
 Select  
      'IdMovimento' = a.IdMovimento,  
      'Ordem' = 1,  
      'QuantidadeLinha' = 1,  
      'LinhaCabecalho' = '1'  -- TipoLinha  
          + REPLACE(Convert(VARCHAR(10), GETDATE(), 103), '/', '') -- Data Corrente
          + REPLACE(CONVERT(VARCHAR(8), GETDATE(), 108), ':', '') 
          + dbo.fn_ReturnFixedWithChar('0', 14, b.CGC) -- cnpj do distribuidor  
          + Space(1)
          + dbo.fn_ReturnFixedWithChar('0', 15,cast(Isnull(c.int_nro_PedidoSite, 0) as varchar(15))) -- Número do pedido OL
		  + Space(15)   
          + Space(20)   
	 From  
      Mov_Estoque a With(Nolock)  
		inner join  
     Tab_Empresa b With(Nolock)  
			on a.IdEmpresa = b.IdEmpresa   
        inner join  
      Mov_Estoque_Complementos c With(Nolock)  
			on a.IdMovimento = c.fk_int_IdMovimento   
Where  
      a.IdMovimento = @int_IdMovimento  
    ),  
    Dados_Nota  
    As  
    (  
     Select  
      'IdMovimento' = a.IdMovimento,  
      'Ordem' = 2,  
      'QuantidadeLinha' = 1,  
      'LinhaDadosNota' = '2' -- TipoLinha  
               + Space(8)   
			   + Space(6)   
			   + REPLACE(Convert(Varchar, d.dte_Emissao, 103), '/', '') -- Dt Emissao NF  
               + dbo.fn_ReturnFixedWithChar('0', 14, b.CGC) -- cnpj do cliente 
			   + dbo.fn_ReturnFixedWithChar('0', 6, d.int_NumeroDocumento) -- NumeroNF,  
               + dbo.fn_ReturnFixedWithChar('0', 3, d.int_Serie) -- SerieNF  
			   + Space(8)                                   
               + dbo.fn_ReturnFixedWithChar('0', 9, d.int_NumeroDocumento) -- NumeroNF,  
               + dbo.fn_ReturnFixedWithChar('0', 3, d.int_Serie) -- SerieNF
			   + Space(14)     
	From  
      Mov_Estoque a With(Nolock)  -- Mov_Estoque - Venda  
		  inner join  
      Tab_Cadastro b With(Nolock)  
			on a.IdCadastro = b.Codinome  
		  Inner join  
      Tab_Empresa c With(Nolock)  
			on a.IdEmpresa = c.IdEmpresa   
          inner join  
      NfEletronica as d with(nolock)  
			on a.IdMovimento = d.fk_int_Idmovimento  
     Where  
      a.IdMovimento = @int_IdMovimento  
    ),  
   
   Totais_Nota
	 as 
	 (     
	    Select  
      'IdMovimento' = a.IdMovimento,  
      'Ordem' = 3,  
      'QuantidadeLinha' = 1,  
      'LinhaTotaisNota' = '3'                                   -- TipoLinha  
               + Space(8)
			   + Space(8)
			   + Space(8)
			   + dbo.fn_ReturnFixedWithChar('0', 8, cast(replace(replace(Convert(Decimal(13,2),Isnull(c.cur_Itens,0)),',',''),'.','') as varchar(8)))-- ValorTotalLiq
			   + dbo.fn_ReturnFixedWithChar('0', 8, cast(replace(replace(Convert(Decimal(13,2),Isnull(c.cur_NF,0)),',',''),'.','') as varchar(8))) -- ValorTotal NF 
			   + Space(8)
			   + Space(8)
			   + Space(31)     
   From  
      Mov_Estoque a With(Nolock)  -- Mov_Estoque - Venda  
		 inner join  
       NfEletronica as b with(nolock)  
		   on a.IdMovimento = b.fk_int_Idmovimento  
         inner join  
       TotalNf as c with(nolock)  
		   on b.fk_int_TotalNF = c.pk_int_TotalNF  
   WHERE  
       a.IdMovimento = @int_IdMovimento
	),

   Impostos_Nota
	  As
	  ( Select  
      'IdMovimento' = a.IdMovimento,  
      'Ordem' = 4,  
      'QuantidadeLinha' = 1,  
      'ImpostosNota' = '4'                                   -- TipoLinha  
                + Space(8)  
                + Space(8)  
                + Space(8)  
			    + Space(8)   
			    + Space(47)     
   From  
      Mov_Estoque a With(Nolock)  -- Mov_Estoque - Venda  
   WHERE  
       a.IdMovimento = @int_IdMovimento
	),
	   Itens_Nota  
    As  
    (  
     Select  
      'empresa' = d.idempresa,
	  'IdMovimento' = a.IdMovimento,  
      'Ordem' = 5,  
      'QuantidadeLinha' = 1,  
      'LinhaItensNota' = '5'      -- TipoLinha  
               + dbo.fn_ReturnFixedWithChar('0', 13, cast(c.códigobarra as varchar(14))) -- Ean  
               + Space(7)                                -- CodProdEntire (CodProdPLK)  
               + dbo.fn_ReturnFixedWithChar('0', 8, cast(cast(b.QuantidadeUsada as int) as varchar(10))) -- QuantidadeFaturada  
               + Space(3)                                 -- TipoEmbalagem  
               + dbo.fn_ReturnFixedWithChar('0', 8, cast(replace(replace(Convert(Decimal(13,2),(Isnull(d.cur_CustoComercial,0))),',',''),'.','') as varchar(8))) --Preço comercial
			   + dbo.fn_ReturnFixedWithChar('0', 4, cast(replace(replace(Convert(Decimal(13,2),(Isnull(b.PercDesconto,0) * d.cur_CustoComercial/100)),',',''),'.','') as varchar(5))) -- DescontoComercial %  
               + dbo.fn_ReturnFixedWithChar('0', 8, cast(replace(replace(Convert(Decimal(13,2),(Isnull(d.cur_CustoComercial,0) * b.PercDesconto)),',',''),'.','') as varchar(5)))   --DescontoComercial R$
               + Space(8)
			   + Space(4) 
               + dbo.fn_ReturnFixedWithChar('0', 8, cast(replace(replace(Convert(Decimal(13,2),(Isnull(b.ValorUnitárioUsado,0) + Isnull(b.ValorDesconto,0))),',',''),'.','') as varchar(8)))        -- ValorBrutoUnit  
               + Replace(Space(4), Space(1), '0')                    -- FillerLinha5 
     From  
      Mov_Estoque a WITH(NOLOCK)  
       inner join  
      Mov_Estoque_Detalhes b WITH(NOLOCK)  
        on a.IdMovimento = b.IdMovimento  
       inner join  
      Tab_Estoque c WITH(NOLOCK)  
        on b.IdItem = c.IdItem  
	   inner join 
	  Tab_EstoqueEmpresa d
	    on c.IdItem = d.IdItem and a.IdEmpresa = d.IdEmpresa 
     
	 WHERE  
      a.IdMovimento = @int_IdMovimento  
	   
    ),  
    Verificadores_Somadores_Nota  
    As  
    (  
     SELECT  
      'IdMovimento' = a.IdMovimento,  
      'Ordem' = 6,  
      'QuantidadeLinha' = 1,  
      'LinhaVerifSomadoresNota' = '6' -- TipoLinha  
                   + dbo.fn_ReturnFixedWithChar('0', 4, cast((cast(Count(*) as int)) as varchar(5))) -- QtdeItens  
                   + Replace(Space(75), Space(1), '0') -- FillerLinha4  
     FROM  
      Mov_Estoque a WITH(NOLOCK)  
       inner join  
      Mov_Estoque_Detalhes b WITH(NOLOCK)  
        on a.IdMovimento = b.IdMovimento  
     WHERE  
      a.IdMovimento = @int_IdMovimento  
     GROUP BY  
      a.IdMovimento  
    )  
    
    --Insere na tabela para gerar o arquivo  
    Insert Into tmp_GerarArquivoRetornoPedido  
    (  
     str_arquivo,  
     int_idmovimento  
    )  
    Select  
     'Linha' = aa.LinhaCabecalho  
          + Case Row_Number() Over (Order By aa.Ordem Asc)   --Registro tipo “9” – Finalizador  
            When Count(1) Over (Partition By aa.IdMovimento)  
             Then '' --@LineBreak  
             
			 Else ''  
           End,  
     aa.IdMovimento  
    From  
     (            
      Select      --1 Registro Tipo “1’” – Cabeçalho  
       a.IdMovimento,   
       a.Ordem,  
       a.QuantidadeLinha,  
       a.LinhaCabecalho  
      From  
       Cabecalho_Nota As a  
        
      Union All  
  
      Select      --2 Registro Tipo “2” – Linha Dados da Nota
       a.IdMovimento,   
       a.Ordem,  
       a.QuantidadeLinha,  
       a.LinhaDadosNota  
      From  
       Dados_Nota As a  
  
      Union All  
  
      Select      --3 Registro Tipo “3” – Linha Itens da Nota   
       a.IdMovimento,   
       a.Ordem,  
       a.QuantidadeLinha,  
       a.LinhaTotaisNota
      From  
       Totais_Nota As a  
  
      Union All  
  
      Select      --4 Registro Tipo “4” – Impostos da Nota  
       a.IdMovimento,   
       a.Ordem,  
       a.QuantidadeLinha,  
       a.ImpostosNota  
      From  
       Impostos_Nota As a  

	    Union All  
  
      Select      --5 Registro Tipo “4” – Itens da Nota  
       a.IdMovimento,   
       a.Ordem,  
       a.QuantidadeLinha,  
       a.LinhaItensNota  
      From  
       Itens_Nota As a  

	   Union All  
  
      Select      --6 Registro Tipo “5” –  Verificadores_Somadores_Nota
       a.IdMovimento,   
       a.Ordem,  
       a.QuantidadeLinha,  
       a.LinhaVerifSomadoresNota  
      From  
       Verificadores_Somadores_Nota As a 
  
     ) As aa  
    Order By  
     aa.Ordem Asc  
      
    --Veirifica se o arquivo tem mais de 3 linhas  
    Set @int_ContadorLinha = 0  
    Set @int_ContadorLinha = (Select Count(1) From tmp_GerarArquivoRetornoPedido Where int_idmovimento = @int_IdMovimento)  
  
    If IsNull(@int_ContadorLinha, 0) > 2  
     Begin  
      --Gravar arquivo na Pasta  
      Set @str_NomeCompletoArquivo = @str_PathGeracaoArquivo + 'NOLPDV' +  @str_CNPJEmpresa  + (select FORMAT(a.DataMovimento, 'yyyyMMdd' + REPLACE(Convert(Varchar, a.dte_conclusao_movimento, 108),':', '') )  from Mov_Estoque a where IdMovimento = @int_IdMovimento) + '.NOL'  
  
      Exec sp_mng_exporta_txt @str_SelectGerarArquivo, @str_NomeCompletoArquivo, @str_InstanciaSQL  
  
      --Verificar se o arquivo existe na pasta para dar o update de respondido        
      Set @bit_VerificaArquivoExiste = 0    
    
      Exec sp_VerificaArquivoExiste @str_NomeCompletoArquivo, @exists = @bit_VerificaArquivoExiste output    
  
      /* Atualizar que o Movimento gerou o arquivo de retorno*/  
      If @bit_VerificaArquivoExiste = 1  
       Begin  
        Insert Into Tab_GerarArquivoFarmaAutomatico  
        (  
         int_idmovimento,  
         int_FarmaConfig,  
         int_enumFarmaLayouts,  
         dte_ArquivoGerado,  
         bit_ArquivoGerado,  
         bit_LiberarOrcamento  
        )  
        Values  
        (  
         @int_IdMovimento,  
         0,  
         0,  
         Getdate(),  
         1,  
         0  
        )  
       End  
     End  
  
    Delete From tmp_GerarArquivoRetornoPedido Where int_idmovimento = @int_IdMovimento  
  
    Fetch Next From cur_NotaFiscal Into @int_IdMovimento, @int_NumeroDocumento, @str_CNPJEmpresa; --verificar essa linha  
   End  
   
  Close cur_NotaFiscal   
  Deallocate cur_NotaFiscal  
 End Try  
  
 Begin Catch  
  Set @ErrorMessage = 'Ocorreu um erro na procedure ''usp_mng_GerarArquivoNotaFiscalRessarcimento'' responsável por gerar o arquivo de nota fiscal( Informação para ressarcimento) : ' + Error_Message();  
  Set @ErrorSeverity = Error_Severity();  
  Set @ErrorState = Error_State();  
  Raiserror (@ErrorMessage, @ErrorSeverity, @ErrorState);  
 End Catch  
  

GO

GRANT EXEC ON usp_mng_GerarArquivoNotaFiscalRessarcimento TO PUBLIC
GO
