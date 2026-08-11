######
# Script para gerar dados de exemplo para o exercício de Data Warehouse TechMart
######

import csv
import random
import datetime
from faker import Faker
import pandas as pd


fake = Faker('pt_BR')
random.seed(42)

def gerar_regioes():
    """Gerar dados de regiões"""
    regioes = [
        {'region_id': 1, 'region_name': 'Norte', 'region_code': 'N'},
        {'region_id': 2, 'region_name': 'Nordeste', 'region_code': 'NE'},
        {'region_id': 3, 'region_name': 'Centro-Oeste', 'region_code': 'CO'},
        {'region_id': 4, 'region_name': 'Sudeste', 'region_code': 'SE'},
        {'region_id': 5, 'region_name': 'Sul', 'region_code': 'S'}
    ]
    
    with open('regions.csv', 'w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=['region_id', 'region_name', 'region_code'])
        writer.writeheader()
        writer.writerows(regioes)
    
    return regioes

def gerar_categorias():
    """Gerar dados de categorias de produtos"""
    categorias = [
        {'category_id': 1, 'category_name': 'Smartphones', 'category_description': 'Telefones celulares e smartphones'},
        {'category_id': 2, 'category_name': 'Laptops', 'category_description': 'Notebooks e laptops'},
        {'category_id': 3, 'category_name': 'Tablets', 'category_description': 'Tablets e iPads'},
        {'category_id': 4, 'category_name': 'Acessórios', 'category_description': 'Cabos, capas, carregadores'},
        {'category_id': 5, 'category_name': 'Games', 'category_description': 'Jogos e consoles'},
        {'category_id': 6, 'category_name': 'Audio', 'category_description': 'Fones de ouvido e caixas de som'},
        {'category_id': 7, 'category_name': 'Wearables', 'category_description': 'Smartwatches e fitness trackers'}
    ]
    
    with open('categories.csv', 'w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=['category_id', 'category_name', 'category_description'])
        writer.writeheader()
        writer.writerows(categorias)
    
    return categorias

def gerar_fornecedores():
    """Gerar dados de fornecedores"""
    fornecedores = [
        {'supplier_id': 1, 'supplier_name': 'TechDistribuidor Ltda', 'contact_email': 'contato@techdist.com.br', 'phone': '11999887766'},
        {'supplier_id': 2, 'supplier_name': 'Eletrônicos Brasil SA', 'contact_email': 'vendas@eletronicosb.com.br', 'phone': '21988776655'},
        {'supplier_id': 3, 'supplier_name': 'Gadgets & Cia', 'contact_email': 'comercial@gadgetsecia.com.br', 'phone': '31977665544'},
        {'supplier_id': 4, 'supplier_name': 'Import Tech', 'contact_email': 'importacao@importtech.com.br', 'phone': '47966554433'},
        {'supplier_id': 5, 'supplier_name': 'Digital Solutions', 'contact_email': 'suporte@digitalsol.com.br', 'phone': '85955443322'}
    ]
    
    with open('suppliers.csv', 'w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=['supplier_id', 'supplier_name', 'contact_email', 'phone'])
        writer.writeheader()
        writer.writerows(fornecedores)
    
    return fornecedores

def gerar_produtos(categorias, fornecedores):
    """Gerar dados de produtos"""
    produtos_por_categoria = {
        1: ['iPhone 14', 'Samsung Galaxy S23', 'Xiaomi Redmi Note 12', 'Motorola Edge 30', 'OnePlus 11'],
        2: ['MacBook Air M2', 'Dell XPS 13', 'Lenovo ThinkPad X1', 'HP Pavilion 15', 'Asus ZenBook 14'],
        3: ['iPad Air', 'Samsung Galaxy Tab S8', 'Lenovo Tab P11', 'Huawei MatePad', 'Amazon Fire HD 10'],
        4: ['Cabo USB-C', 'Carregador Wireless', 'Capa iPhone', 'Película Protetora', 'Suporte Celular'],
        5: ['PlayStation 5', 'Xbox Series X', 'Nintendo Switch', 'Steam Deck', 'Controle Pro'],
        6: ['AirPods Pro', 'Sony WH-1000XM4', 'JBL Flip 6', 'Bose QuietComfort', 'Beats Studio Buds'],
        7: ['Apple Watch Series 8', 'Samsung Galaxy Watch 5', 'Fitbit Versa 4', 'Garmin Venu 2', 'Amazfit GTR 3']
    }
    
    produtos = []
    product_id = 1
    
    for categoria in categorias:
        cat_id = categoria['category_id']
        nomes_produtos = produtos_por_categoria.get(cat_id, [])
        
        for nome in nomes_produtos:
            if cat_id in [1, 2]: 
                price = random.uniform(800, 5000)
            elif cat_id in [3, 5]:  
                price = random.uniform(300, 2000)
            elif cat_id in [6, 7]: 
                price = random.uniform(150, 1500)
            else:  
                price = random.uniform(20, 200)
            
            produto = {
                'product_id': product_id,
                'product_name': nome,
                'category_id': cat_id,
                'supplier_id': random.choice(fornecedores)['supplier_id'],
                'price': round(price, 2),
                'cost': round(price * 0.6, 2),  # 60% do preço
                'stock_quantity': random.randint(10, 500),
                'created_date': fake.date_between(start_date='-2y', end_date='-1y')
            }
            produtos.append(produto)
            product_id += 1
    
    with open('products.csv', 'w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=['product_id', 'product_name', 'category_id', 'supplier_id', 'price', 'cost', 'stock_quantity', 'created_date'])
        writer.writeheader()
        writer.writerows(produtos)
    
    return produtos

def gerar_clientes(regioes):
    """Gerar dados de clientes"""
    clientes = []
    
    for i in range(1, 1001):  
        cliente = {
            'customer_id': i,
            'first_name': fake.first_name(),
            'last_name': fake.last_name(),
            'email': fake.email(),
            'phone': fake.phone_number(),
            'birth_date': fake.date_of_birth(minimum_age=18, maximum_age=70),
            'gender': random.choice(['M', 'F']),
            'city': fake.city(),
            'state': fake.state_abbr(),
            'region_id': random.choice(regioes)['region_id'],
            'registration_date': fake.date_between(start_date='-3y', end_date='-1m'),
            'customer_segment': random.choice(['Bronze', 'Prata', 'Ouro', 'Platinum'])
        }
        clientes.append(cliente)
    
    with open('customers.csv', 'w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=['customer_id', 'first_name', 'last_name', 'email', 'phone', 'birth_date', 'gender', 'city', 'state', 'region_id', 'registration_date', 'customer_segment'])
        writer.writeheader()
        writer.writerows(clientes)
    
    return clientes

def gerar_pedidos_e_itens(clientes, produtos):
    """Gerar dados de pedidos e itens dos pedidos"""
    pedidos = []
    itens_pedidos = []
    
    order_id = 1
    item_id = 1
    
    start_date = datetime.date.today() - datetime.timedelta(days=730)
    end_date = datetime.date.today() - datetime.timedelta(days=1)
    
    for _ in range(3000):  
        order_date = fake.date_between(start_date=start_date, end_date=end_date)
        customer = random.choice(clientes)
        
        days_ago = (datetime.date.today() - order_date).days
        if days_ago < 7:
            status = random.choice(['Processando', 'Enviado', 'Entregue'])
        elif days_ago < 30:
            status = random.choice(['Enviado', 'Entregue'])
        else:
            status = 'Entregue'
        
        channel = random.choice(['Website', 'Marketplace'])
        
        pedido = {
            'order_id': order_id,
            'customer_id': customer['customer_id'],
            'order_date': order_date,
            'status': status,
            'channel': channel,
            'shipping_cost': round(random.uniform(0, 50), 2)
        }
        pedidos.append(pedido)
        

        num_itens = random.randint(1, 5)
        produtos_pedido = random.sample(produtos, min(num_itens, len(produtos)))
        
        total_amount = 0
        for produto in produtos_pedido:
            quantity = random.randint(1, 3)
            unit_price = produto['price']

            if random.random() < 0.2:  # 
                discount = random.uniform(0.05, 0.25)
                unit_price = unit_price * (1 - discount)
            
            item_total = quantity * unit_price
            total_amount += item_total
            
            item = {
                'item_id': item_id,
                'order_id': order_id,
                'product_id': produto['product_id'],
                'quantity': quantity,
                'unit_price': round(unit_price, 2),
                'total_price': round(item_total, 2)
            }
            itens_pedidos.append(item)
            item_id += 1
        

        pedido['total_amount'] = round(total_amount + pedido['shipping_cost'], 2)
        order_id += 1
    

    with open('orders.csv', 'w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=['order_id', 'customer_id', 'order_date', 'status', 'channel', 'total_amount', 'shipping_cost'])
        writer.writeheader()
        writer.writerows(pedidos)
    

    with open('order_items.csv', 'w', newline='', encoding='utf-8') as file:
        writer = csv.DictWriter(file, fieldnames=['item_id', 'order_id', 'product_id', 'quantity', 'unit_price', 'total_price'])
        writer.writeheader()
        writer.writerows(itens_pedidos)
    
    return pedidos, itens_pedidos

def main():
    """Função principal para gerar todos os dados"""
    print("Gerando dados de exemplo para TechMart...")
    
    print("1. Gerando regiões...")
    regioes = gerar_regioes()
    
    print("2. Gerando categorias...")
    categorias = gerar_categorias()
    
    print("3. Gerando fornecedores...")
    fornecedores = gerar_fornecedores()
    
    print("4. Gerando produtos...")
    produtos = gerar_produtos(categorias, fornecedores)
    
    print("5. Gerando clientes...")
    clientes = gerar_clientes(regioes)
    
    print("6. Gerando pedidos e itens...")
    pedidos, itens_pedidos = gerar_pedidos_e_itens(clientes, produtos)
    
    print(f"""
Dados gerados com sucesso!

Resumo:
- Regiões: {len(regioes)}
- Categorias: {len(categorias)}
- Fornecedores: {len(fornecedores)}
- Produtos: {len(produtos)}
- Clientes: {len(clientes)}
- Pedidos: {len(pedidos)}
- Itens de pedidos: {len(itens_pedidos)}

Arquivos CSV criados:
- regions.csv
- categories.csv
- suppliers.csv
- products.csv
- customers.csv
- orders.csv
- order_items.csv
    """)

if __name__ == "__main__":
    main()

