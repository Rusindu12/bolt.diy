import json, random, math

# Tiny dataset: intent classification (greeting, math, time, general)
data = [
 ("hello", "greeting"), ("hi", "greeting"), ("hey there", "greeting"), ("good morning", "greeting"),
 ("what time is it", "time"), ("current time", "time"), ("date today", "time"),
 ("calculate 2+2", "math"), ("what is 5*6", "math"), ("compute 10/2", "math"),
 ("tell me a joke", "general"), ("explain ai", "general"), ("how are you", "general"),
]
labels = ["greeting","math","time","general"]
li = {l:i for i,l in enumerate(labels)}

# Bag of words vocab
vocab = set()
for t,_ in data:
    for w in t.split():
        vocab.add(w)
vocab = sorted(vocab)
vi = {w:i for i,w in enumerate(vocab)}

def features(text):
    v = [0.0]*len(vocab)
    for w in text.lower().split():
        if w in vi: v[vi[w]] = 1.0
    return v

X = [features(t) for t,_ in data]
y = [li[l] for _,l in data]

# Simple softmax regression via gradient descent
random.seed(0)
W = [[random.uniform(-0.1,0.1) for _ in range(len(vocab))] for _ in range(len(labels))]
b = [0.0]*len(labels)
lr=0.5
for epoch in range(2000):
    for xi,yi in zip(X,y):
        # forward
        logits=[sum(W[k][j]*xi[j] for j in range(len(vocab)))+b[k] for k in range(len(labels))]
        mx=max(logits)
        exps=[math.exp(l-mx) for l in logits]
        s=sum(exps)
        probs=[e/s for e in exps]
        # backward
        for k in range(len(labels)):
            grad = probs[k] - (1.0 if k==yi else 0.0)
            for j in range(len(vocab)):
                W[k][j] -= lr*grad*xi[j]
            b[k] -= lr*grad

# accuracy
correct=0
for xi,yi in zip(X,y):
    logits=[sum(W[k][j]*xi[j] for j in range(len(vocab)))+b[k] for k in range(len(labels))]
    if max(range(len(labels)), key=lambda k: logits[k])==yi: correct+=1
print("train acc", correct/len(X))

out = {"vocab": vocab, "labels": labels, "W": W, "b": b}
with open("weights.json","w") as f:
    json.dump(out, f)
print("saved weights.json")
